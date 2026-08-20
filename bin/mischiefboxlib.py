#!/usr/bin/env python3
"""MischiefBox shared core (registry, input validation, docker cmd building).

Used by both the CLI and the HTTP API. Stdlib only (3.11+).
"""
import json
import os
import subprocess
import time
import tomllib

MISCHIEFBOX_DIR = os.path.expanduser("~/mischiefbox")
REGISTRY_FILE = os.path.join(MISCHIEFBOX_DIR, "registry.toml")
SECRETS_DIR = os.path.join(MISCHIEFBOX_DIR, "secrets")
DISCOVERY_TOKEN_FILE = os.path.join(SECRETS_DIR, "gitea-discovery-token")
TOOLS_DIR = os.path.join(MISCHIEFBOX_DIR, "tools")
PIPELINES_DIR = os.path.join(MISCHIEFBOX_DIR, "pipelines")
RUNS_LOG_FILE = os.path.join(MISCHIEFBOX_DIR, "runs.log")

# Args that may contain secrets - redact in logs
SENSITIVE_ARGS = {"token", "password", "secret", "key", "api_key", "apikey"}

GITEA_URL = os.environ.get("MB_GITEA_URL", "http://localhost:3010")
GITEA_ORG = os.environ.get("MB_GITEA_ORG", "mischiefbox")

# git over Gitea's SSH port; uses the registered deploy key.
GIT_SSH = ("ssh -i {0}/.ssh/id_ed25519 -o StrictHostKeyChecking=no "
           "-o UserKnownHostsFile=/dev/null -p 3022").format(MISCHIEFBOX_DIR)

INPUT_TYPES = ("string", "int", "float", "bool", "enum")

NET_ORDER = {"none": 0, "bridge": 1, "host": 2}


def mount_host_path(mnt):
    """Return the host-side path of a 'host:container:mode' mount string."""
    return mnt.split(":", 1)[0]


def _path_under(child, parent):
    """True if child == parent or is under parent (path-prefix aware)."""
    if child == parent:
        return True
    if parent.endswith("/"):
        return child.startswith(parent)
    return child.startswith(parent + "/")


def check_capabilities(m):
    """Validate [runtime] against [capabilities]. Returns list of problems.

    capabilities declares the MAXIMUM a tool may use; runtime is what it
    actually requests. Any runtime entry beyond the declared capability is a
    violation -> the runner must refuse to start the container.
    """
    problems = []
    caps = m.get("capabilities", {}) or {}
    rt = m.get("runtime", {}) or {}

    net_cap = caps.get("network", "none")
    net_rt = rt.get("network", "none")
    if NET_ORDER.get(net_rt, 0) > NET_ORDER.get(net_cap, 0):
        problems.append(
            f"runtime.network={net_rt} exceeds capabilities.network={net_cap}")

    if rt.get("privileged", False) and not caps.get("privileged", False):
        problems.append("runtime.privileged=true but capabilities.privileged=false")

    if rt.get("pid") == "host" and not caps.get("pid", False):
        problems.append("runtime.pid=host but capabilities.pid=false")

    cap_mounts = caps.get("mounts", [])
    for mnt in rt.get("mounts", []):
        host = mount_host_path(mnt)
        allowed = any(_path_under(host, cap) for cap in cap_mounts)
        if not allowed:
            problems.append(
                f"runtime.mount '{host}' not under declared capabilities.mounts "
                f"{cap_mounts or []}")

    return problems


def load_toml(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def load_registry():
    return load_toml(REGISTRY_FILE)


def find_tool(name):
    reg = load_registry()
    for t in reg.get("tools", []):
        if t["name"] == name:
            return t
    return None


def tool_dir(tool):
    return os.path.join(MISCHIEFBOX_DIR, tool["source"])


def load_tool_manifest(tool):
    return load_toml(os.path.join(tool_dir(tool), "tool.toml"))


def coerce_value(name, spec, raw):
    """Validate+coerce one input value from its CLI string; returns value."""
    t = spec.get("type", "string")
    if t not in INPUT_TYPES:
        raise ValueError(f"input '{name}': unknown type '{t}'")
    if t == "bool":
        if isinstance(raw, bool):
            return raw
        s = str(raw).lower()
        if s in ("true", "1", "yes", "on"):
            return True
        if s in ("false", "0", "no", "off"):
            return False
        raise ValueError(f"input '{name}': expected bool, got '{raw}'")
    if t == "int":
        try:
            return int(raw)
        except (TypeError, ValueError):
            raise ValueError(f"input '{name}': expected int, got '{raw}'")
    if t == "float":
        try:
            return float(raw)
        except (TypeError, ValueError):
            raise ValueError(f"input '{name}': expected float, got '{raw}'")
    if t == "enum":
        allowed = spec.get("values", [])
        if raw not in allowed:
            raise ValueError(
                f"input '{name}': '{raw}' not in allowed values {allowed}")
        return raw
    return str(raw)


def validate_inputs(manifest, cli_args):
    """Parse CLI args against the declared input schema.

    cli_args: list of strings. For each declared input:
      - flag input:  --name VALUE  (bool: --name or --name=VALUE)
      - env input:   --name VALUE  (mapped to an env var in docker)
      - positional:  bare VALUE in declaration order
    Unknown flags / missing required / bad types -> ValueError.
    Returns (dict {input_name: value}, list legacy_args).
    """
    specs = manifest.get("run", {}).get("inputs", {}) or {}
    if not specs:
        # No schema: pass args through verbatim (legacy tools).
        return {}, list(cli_args)

    parsed = {}
    used = set()
    positionals = []
    i = 0
    while i < len(cli_args):
        a = cli_args[i]
        if a.startswith("--") and "=" in a:
            key, val = a[2:].split("=", 1)
            if key not in specs:
                raise ValueError(f"unknown input '--{key}'")
            parsed[key] = coerce_value(key, specs[key], val)
            used.add(key)
        elif a.startswith("--"):
            key = a[2:]
            if key not in specs:
                raise ValueError(f"unknown input '--{key}'")
            spec = specs[key]
            if spec.get("type") == "bool":
                parsed[key] = True
                used.add(key)
            else:
                if i + 1 >= len(cli_args):
                    raise ValueError(f"input '--{key}' requires a value")
                parsed[key] = coerce_value(key, spec, cli_args[i + 1])
                used.add(key)
                i += 1
        else:
            positionals.append(a)
        i += 1

    pos_specs = [k for k, s in specs.items() if s.get("positional")]
    if positionals:
        if len(positionals) > len(pos_specs):
            raise ValueError("too many positional arguments")
        for key, val in zip(pos_specs, positionals):
            if key in used:
                raise ValueError(f"input '{key}' given twice")
            parsed[key] = coerce_value(key, specs[key], val)
            used.add(key)

    for key, spec in specs.items():
        if key not in used:
            if "default" in spec:
                parsed[key] = spec["default"]
            elif spec.get("required", False):
                raise ValueError(f"missing required input '{key}'")

    return parsed, []


def docker_run_args(m, input_values, legacy_args):
    run = m["run"]
    rt = m.get("runtime", {})
    cmd = ["docker", "run", "--rm"]
    net = rt.get("network", "none")
    if net != "none":
        cmd += ["--network", net]
    if rt.get("privileged", False):
        cmd.append("--privileged")
    if rt.get("pid") == "host":
        cmd += ["--pid", "host"]
    for mnt in rt.get("mounts", []):
        cmd += ["-v", mnt]
    for k, v in rt.get("environment", {}).items():
        cmd += ["-e", f"{k}={v}"]

    specs = run.get("inputs", {}) or {}
    for key, spec in specs.items():
        if key in input_values and spec.get("env"):
            val = input_values[key]
            if isinstance(val, bool):
                val = "true" if val else "false"
            cmd += ["-e", f"{spec['env']}={val}"]

    cmd.append(run["image"])
    cmd += run.get("command", [])
    cmd += legacy_args

    if specs:
        for key, spec in specs.items():
            if key not in input_values:
                continue
            val = input_values[key]
            if spec.get("flag"):
                if spec.get("type") == "bool":
                    if val:
                        cmd += [spec["flag"]]
                else:
                    cmd += [spec["flag"], str(val)]
            elif spec.get("positional"):
                cmd += [str(val)]
    return cmd


def build_docker_command(tool_name, cli_args):
    """Validate + build the docker command for a tool. Returns
    (docker_cmd, manifest). Raises ValueError on unknown tool / bad input /
    capability violation."""
    tool = find_tool(tool_name)
    if not tool:
        raise ValueError(f"unknown tool '{tool_name}'")
    m = load_tool_manifest(tool)
    problems = check_capabilities(m)
    if problems:
        raise ValueError(f"tool '{tool_name}' capability violation: "
                         + "; ".join(problems))
    input_values, legacy_args = validate_inputs(m, cli_args)
    docker_cmd = docker_run_args(m, input_values, legacy_args)
    return docker_cmd, m


def render_output(m, stdout_text):
    """Render a tool's stdout according to its [run.outputs] schema.
    Returns (text_to_print, ok_bool)."""
    outs = m.get("run", {}).get("outputs") or {}
    if not outs:
        return stdout_text, True
    fmt = outs.get("format", "json")
    if fmt != "json":
        return stdout_text, True
    try:
        data = json.loads(stdout_text)
    except json.JSONDecodeError:
        return stdout_text, False
    fields = outs.get("fields") or {}
    problems = []
    if fields:
        for fname, ftype in fields.items():
            if fname not in data:
                problems.append(f"missing field '{fname}'")
                continue
            v = data[fname]
            if ftype == "string" and not isinstance(v, str):
                problems.append(f"field '{fname}': expected string, got {type(v).__name__}")
            elif ftype == "int" and not isinstance(v, int):
                problems.append(f"field '{fname}': expected int, got {type(v).__name__}")
            elif ftype == "bool" and not isinstance(v, bool):
                problems.append(f"field '{fname}': expected bool, got {type(v).__name__}")
    return json.dumps(data, indent=2), not problems


def list_tools():
    """Return [{name, version, description}] in registry order."""
    reg = load_registry()
    rows = []
    for t in reg.get("tools", []):
        try:
            m = load_tool_manifest(t)
            meta = m.get("meta", {})
            rows.append({
                "name": meta.get("name", t["name"]),
                "version": meta.get("version", "?"),
                "description": meta.get("description", ""),
            })
        except FileNotFoundError:
            rows.append({"name": t["name"], "version": "?",
                         "description": "manifest missing"})
    return rows


# --- V0.8 run history logging ---

def _redact_args(args, manifest):
    """Redact sensitive values from args for logging."""
    specs = manifest.get("run", {}).get("inputs", {}) or {}
    redacted = []
    skip_next = False
    for i, arg in enumerate(args):
        if skip_next:
            skip_next = False
            redacted.append("***")
            continue
        if arg.startswith("--"):
            key = arg.lstrip("-").split("=")[0]
            if any(s in key.lower() for s in SENSITIVE_ARGS):
                if "=" in arg:
                    redacted.append(f"--{key}=***")
                else:
                    redacted.append(arg)
                    skip_next = True
            elif "=" in arg:
                k, v = arg.split("=", 1)
                if any(s in k.lower() for s in SENSITIVE_ARGS):
                    redacted.append(f"{k}=***")
                else:
                    redacted.append(arg)
            else:
                redacted.append(arg)
        else:
            redacted.append(arg)
    return redacted


def log_run(tool, args, exit_code, stdout_preview="", stderr_preview="",
            duration_ms=0, source="cli", manifest=None):
    """Append a run entry to runs.log (JSONL format)."""
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "tool": tool,
        "args": _redact_args(args, manifest) if manifest else args,
        "exit_code": exit_code,
        "stdout_preview": (stdout_preview[:200] + "...") if len(stdout_preview) > 200 else stdout_preview,
        "stderr_preview": (stderr_preview[:200] + "...") if len(stderr_preview) > 200 else stderr_preview,
        "duration_ms": duration_ms,
        "source": source,
    }
    try:
        with open(RUNS_LOG_FILE, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        pass  # best effort - don't fail the run because of logging


def log_run_start(tool, args, source="cli"):
    """Log the start of a run. Returns start_time for later use."""
    return time.time()


def log_run_end(tool, args, exit_code, start_time, stdout="", stderr="",
                source="cli", manifest=None):
    """Log the end of a run with timing info."""
    duration_ms = int((time.time() - start_time) * 1000)
    log_run(tool, args, exit_code,
            stdout_preview=stdout[:500] if stdout else "",
            stderr_preview=stderr[:500] if stderr else "",
            duration_ms=duration_ms, source=source, manifest=manifest)


def read_history(tool=None, last=20):
    """Read run history from runs.log. Returns list of entries, most recent first."""
    entries = []
    if not os.path.isfile(RUNS_LOG_FILE):
        return entries
    try:
        with open(RUNS_LOG_FILE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    if tool and entry.get("tool") != tool:
                        continue
                    entries.append(entry)
                except json.JSONDecodeError:
                    continue
    except OSError:
        return []
    entries.reverse()
    return entries[:last]


# --- V0.5 discovery: registry.toml is derived from the Gitea org ---

def discovery_token():
    try:
        with open(DISCOVERY_TOKEN_FILE) as f:
            return f.read().strip()
    except OSError:
        raise ValueError("no discovery token at " + DISCOVERY_TOKEN_FILE +
                         " (run: mb token <sha1>)")


def _gitea(path):
    """GET a Gitea API path with the discovery token; returns parsed JSON."""
    import urllib.request
    req = urllib.request.Request(GITEA_URL + "/api/v1" + path,
                                 headers={"Authorization": "token " + discovery_token()})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise ValueError(f"gitea API {path}: HTTP {e.code}")


def _fetch_tool_toml(repo):
    """Fetch a repo's tool.toml via the raw API. Returns parsed dict or None."""
    import urllib.request
    req = urllib.request.Request(
        f"{GITEA_URL}/api/v1/repos/{GITEA_ORG}/{repo}/raw/tool.toml",
        headers={"Authorization": "token " + discovery_token()})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return tomllib.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None  # not a tool repo
        raise ValueError(f"gitea raw tool.toml {repo}: HTTP {e.code}")
    except tomllib.TOMLDecodeError as e:
        raise ValueError(f"repo '{repo}' tool.toml is invalid TOML: {e}")


def discover_repos():
    """Query the Gitea org for tool repos (those with a valid tool.toml).
    Returns [{name, source}] — source is the local clone path."""
    repos = _gitea(f"/orgs/{GITEA_ORG}/repos?limit=100&page=1")
    found = []
    for r in repos:
        name = r["name"]
        m = _fetch_tool_toml(name)
        if not m:
            continue
        meta = m.get("meta", {})
        if meta.get("name", name) != name:
            raise ValueError(
                f"repo '{name}': [meta].name='{meta.get('name')}' does not match repo name")
        found.append({"name": name, "source": os.path.join("tools", name)})
    return sorted(found, key=lambda t: t["name"])


def _sync_repo(repo, local_dir):
    """Clone or pull a repo into local_dir. Returns True if changed/created.
    On diverged history, resets hard to origin/main."""
    if os.path.isdir(os.path.join(local_dir, ".git")):
        env = {**os.environ, "GIT_SSH_COMMAND": GIT_SSH}
        if subprocess.run(["git", "-C", local_dir, "pull", "--quiet", "--ff-only"],
                          env=env).returncode != 0:
            subprocess.run(["git", "-C", local_dir, "fetch", "--quiet"], env=env)
            subprocess.run(
                ["git", "-C", local_dir, "reset", "--hard", "--quiet",
                 "origin/" + _default_branch(local_dir)],
                env=env)
        return True
    os.makedirs(os.path.dirname(local_dir), exist_ok=True)
    url = f"ssh://git@TheBarracks:3022/{GITEA_ORG}/{repo}.git"
    r = subprocess.run(
        ["git", "clone", "--quiet", url, local_dir],
        env={**os.environ, "GIT_SSH_COMMAND": GIT_SSH})
    if r.returncode != 0:
        raise ValueError(f"clone failed for '{repo}'")
    return True


def _default_branch(local_dir):
    """Return the remote HEAD branch name (main or master)."""
    r = subprocess.run(
        ["git", "-C", local_dir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
        capture_output=True, text=True)
    if r.returncode == 0:
        return r.stdout.strip().rsplit("/", 1)[-1]
    return "main"


def refresh_registry(verbose=False):
    """Re-derive registry.toml from the Gitea org: discover tool repos, ensure
    local clones, write registry.toml. Returns list of tool names."""
    found = discover_repos()
    for t in found:
        local = os.path.join(MISCHIEFBOX_DIR, t["source"])
        if not os.path.isdir(local):
            print(f"  cloning {t['name']} ...")
            _sync_repo(t["name"], local)
        else:
            print(f"  pulling {t['name']} ...")
            _sync_repo(t["name"], local)
    lines = []
    for t in found:
        lines.append("[[tools]]")
        lines.append(f'name = "{t["name"]}"')
        lines.append(f'source = "{t["source"]}"')
        lines.append("")
    with open(REGISTRY_FILE, "w") as f:
        f.write("\n".join(lines))
    return [t["name"] for t in found]


def describe_tool(name):
    """Return a schema dict for a tool, or None if unknown."""
    tool = find_tool(name)
    if not tool:
        return None
    m = load_tool_manifest(tool)
    meta = m.get("meta", {})
    run = m.get("run", {})
    inputs = {}
    for key, spec in (run.get("inputs", {}) or {}).items():
        inputs[key] = {
            "type": spec.get("type", "string"),
            "required": bool(spec.get("required", False)),
            "default": spec.get("default"),
            "values": spec.get("values"),
            "flag": spec.get("flag"),
            "env": spec.get("env"),
            "positional": bool(spec.get("positional", False)),
            "description": spec.get("description", ""),
        }
    outputs = run.get("outputs") or {}
    caps = m.get("capabilities") or {}
    return {
        "name": meta.get("name", name),
        "version": meta.get("version", "?"),
        "description": meta.get("description", ""),
        "image": run.get("image"),
        "capabilities": caps,
        "inputs": inputs,
        "outputs": {
            "format": outputs.get("format", "json") if outputs else None,
            "fields": outputs.get("fields") or {},
        } if outputs else None,
    }


# --- V0.6 pipelines: chained tool calls ---

PIPELINE_SCHEMA = ("meta", "steps")


def load_pipeline(name):
    """Load a pipeline.toml from ~/mischiefbox/pipelines/<name>/."""
    path = os.path.join(PIPELINES_DIR, name, "pipeline.toml")
    if not os.path.isfile(path):
        raise ValueError(f"unknown pipeline '{name}'")
    try:
        p = load_toml(path)
    except tomllib.TOMLDecodeError as e:
        raise ValueError(f"pipeline '{name}' is invalid TOML: {e}")
    meta = p.get("meta", {})
    if meta.get("name", name) != name:
        raise ValueError(f"pipeline '{name}': [meta].name does not match directory")
    steps = p.get("steps") or []
    if not steps:
        raise ValueError(f"pipeline '{name}': no [[steps]] defined")
    return p


def list_pipelines():
    """Return [{name, version, description, steps}] in name order."""
    rows = []
    if not os.path.isdir(PIPELINES_DIR):
        return rows
    for name in sorted(os.listdir(PIPELINES_DIR)):
        try:
            p = load_pipeline(name)
        except ValueError:
            continue
        meta = p.get("meta", {})
        rows.append({
            "name": name,
            "version": meta.get("version", "?"),
            "description": meta.get("description", ""),
            "steps": len(p.get("steps", [])),
        })
    return rows


def validate_pipeline_inputs(pipeline, cli_args):
    """Validate --key value CLI args against [meta.inputs]. Returns dict."""
    specs = pipeline.get("meta", {}).get("inputs", {}) or {}
    parsed = {}
    i = 0
    while i < len(cli_args):
        a = cli_args[i]
        if a.startswith("--") and "=" in a:
            key, val = a[2:].split("=", 1)
            if key not in specs:
                raise ValueError(f"unknown pipeline input '--{key}'")
            parsed[key] = coerce_value(key, specs[key], val)
        elif a.startswith("--"):
            key = a[2:]
            if key not in specs:
                raise ValueError(f"unknown pipeline input '--{key}'")
            spec = specs[key]
            if spec.get("type") == "bool":
                parsed[key] = True
            else:
                if i + 1 >= len(cli_args):
                    raise ValueError(f"input '--{key}' requires a value")
                parsed[key] = coerce_value(key, spec, cli_args[i + 1])
                i += 1
        else:
            raise ValueError(f"unexpected positional arg '{a}' (pipelines use --key value)")
        i += 1
    for key, spec in specs.items():
        if key not in parsed:
            if "default" in spec:
                parsed[key] = spec["default"]
            elif spec.get("required", False):
                raise ValueError(f"missing required pipeline input '{key}'")
    return parsed


def interpolate(step_args, inputs):
    """Replace {{key}} placeholders in step args with pipeline input values."""
    out = []
    for a in step_args:
        for k, v in inputs.items():
            a = a.replace("{{" + k + "}}", str(v))
        out.append(a)
    return out


def run_pipeline(name, inputs, verbose=False):
    """Execute a pipeline's steps sequentially via docker; fail-fast.
    Returns (exit_code, results) where results is a list of per-step dicts."""
    pipeline = load_pipeline(name)
    steps = pipeline.get("steps", [])
    results = []
    for idx, step in enumerate(steps, 1):
        tool = step.get("tool")
        if not tool:
            return 1, results + [{"error": f"step {idx}: missing 'tool'"}]
        step_args = interpolate(step.get("args", []), inputs)
        if verbose:
            print(f"  [{idx}/{len(steps)}] {tool} {' '.join(step_args)}", flush=True)
        try:
            docker_cmd, m = build_docker_command(tool, step_args)
        except ValueError as e:
            return 1, results + [{"tool": tool, "args": step_args, "error": str(e)}]
        try:
            proc = subprocess.run(docker_cmd, capture_output=True, text=True)
        except FileNotFoundError:
            return 1, results + [{"tool": tool, "args": step_args,
                                  "error": "docker not available"}]
        text, _ok = render_output(m, proc.stdout)
        results.append({"tool": tool, "args": step_args, "stdout": text,
                        "exit_code": proc.returncode, "command": " ".join(docker_cmd)})
        if verbose:
            if proc.stdout.strip():
                print("  " + proc.stdout.strip().replace("\n", "\n  "), flush=True)
            if proc.stderr.strip():
                print("  STDERR: " + proc.stderr.strip().replace("\n", "\n  "),
                      flush=True)
        if proc.returncode != 0:
            return proc.returncode, results
    return 0, results
