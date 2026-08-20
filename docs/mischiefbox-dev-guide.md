# MischiefBox — Tool Development Guide

> The reference for developing tools for the MischiefBox platform on TheBarracks.
> Companion to `Project - DevBox\plan.md` (roadmap) and `ai-notes` (pitfalls).
> Status: V0.7 (CLI + typed I/O + API + capabilities + discovery + pipelines + MCP).

## 1. Platform model

```
mischiefbox/<tool> repo (Gitea org)     ← source of truth
   ├─ tool.toml          the contract: what it is + exactly how to run it
   ├─ Dockerfile         builds the runtime image
   ├─ src/               the tool's actual code
   └─ README.md
        │  docker build + push
        ▼
TheBarracks:3010/mischiefbox/<tool>:<ver>   ← OCI registry (Gitea Packages)
        │  docker run (sandboxed)
        ▼
MischiefBox runner (CLI → later HTTP API / MCP)
```

**Core principle:** `tool.toml` is the contract. The runner never guesses how a tool
works — it only translates the manifest into a `docker run`. Everything a tool needs
to reach or touch must be **declared** in the manifest.

**Discovery (V0.5):** `registry.toml` is *derived*, not hand-written. `mischiefbox refresh`
lists the Gitea org, keeps repos with a valid `tool.toml` (`[meta].name` must equal the
repo name), clones/pulls them into `~/mischiefbox/tools/<name>`, and regenerates
`registry.toml`. Push a new tool repo → run `mischiefbox refresh` → it's registered.

## 2. The tool contract

A tool is a self-contained unit of work that:

- is **parameterized** by declared inputs (no hidden state, no hardcoded host paths);
- runs in a **disposable container**;
- is **observable**: stdout = result, stderr = logs, exit code 0 = success;
- is **safe by default**: no network, no privilege, read-only mounts unless declared.

### 2.1 Manifest reference (`tool.toml`)

```toml
[meta]
name = "tool-name"            # lowercase-hyphen; MUST match repo name
version = "0.1.0"             # semver
description = "one line for `mischiefbox list`"

[run]
image = "TheBarracks:3010/mischiefbox/tool-name:0.1.0"   # image tag in the registry
command = ["/usr/local/bin/tool.sh"]                     # fixed argv[0..]; inputs are appended

[run.inputs]                  # V0.2 typed schema; runner validates BEFORE docker starts
# types: string | int | float | bool | enum
# mapping (choose one): flag="--x" | env="VAR" | positional=true
arg-name = { type = "string", required = true, description = "what it is" }
flag-name = { type = "bool", flag = "--dry-run", default = false, description = "..." }
host = { type = "string", env = "RIG_HOST", default = "192.168.100.207", description = "..." }
cmd = { type = "enum", values = ["run", "move"], positional = true, default = "run" }

[run.outputs]                 # V0.2 optional; tool emits JSON to stdout
format = "json"
fields = { status = "string", moved = "int" }            # validated against stdout

[runtime]                     # HOW to sandbox it — defaults are the safe choice
network = "none"              # none | bridge | host   (default: none)
privileged = false            # avoid unless the tool genuinely needs host/system access
mounts = [                    # narrowest path, not the whole tree
  "/host/path:/container/path:ro",   # :ro | :rw
]
environment = {}              # {"KEY": "value"} — injected at run time, never baked

[capabilities]                # V0.4: the MAXIMUM this tool may use. Runner enforces.
network = "none"              # runtime.network must be <= this (none<bridge<host)
privileged = false            # runtime.privileged=true needs this = true
pid = false                   # runtime.pid="host" needs this = true
mounts = [                    # every runtime mount's host path must be under one of these
  "/host/path",
]
```

### 2.2 Runtime → docker mapping

| `tool.toml`            | `docker run`        |
|------------------------|---------------------|
| `network = "none"`     | *(default, nothing)* |
| `network = "bridge"`   | `--network bridge`  |
| `network = "host"`     | `--network host`    |
| `privileged = true`    | `--privileged`      |
| `mounts = [...]`       | one `-v` per entry  |
| `environment = {...}`  | one `-e K=v` per entry |

### 2.3 I/O conventions

- **stdout** — the result / primary data.
- **stderr** — logs and diagnostics (never mix into stdout).
- **exit 0** — success; any non-zero — failure (runner surfaces it).
- **Tools that produce data write a JSON document to stdout** and declare it in
  `[run.outputs]`; the runner validates it against the declared fields and pretty-prints.
  `mischiefbox describe <tool>` shows the full input/output schema.
- **`--help`** — every tool should support it; the runner passes it through.
- **`--dry-run`** — every tool that writes/moves/deletes MUST support it (print what it
  *would* do, touch nothing). This is the single most valuable habit on this box.
- **JSON gotchas inside containers:** BusyBox awk (alpine) processes backslash escapes
  in `-v var=value` (host mawk doesn't) — pass paths via env (`ENVIRON["..."]`), not
  `-v`. Windows-origin files (ssh configs, pubkeys) are CRLF — `sub(/\r$/, "")` before
  parsing. See `ai-notes` 2026-08-19.

## 3. Repo layout & naming

```
mischiefbox/<tool-name>/
├── tool.toml
├── Dockerfile
├── README.md
└── src/
    └── tool-name.sh | tool-name.py
```

Rules:

- repo name == tool name, under Gitea org `mischiefbox`.
- `src/` holds the code the image copies in.
- `README.md` documents behavior, runtime needs, and why any non-default `[runtime]`
  entries exist.
- **Never** commit secrets, tokens, or host-specific paths into the repo. Secrets are
  supplied via `[runtime].environment` (or an env file) at run time only.

## 4. Development workflow

### 4.1 Develop the script standalone first

Write and test the logic on the host against real inputs before touching Docker. It must
be:

- **idempotent** — safe to re-run (movers/backup move real data; design for re-entry);
- **dry-run aware** — `--dry-run` for any mutating action;
- **parameterized** — host paths and targets come from argv/env; the manifest supplies
  them, so the same image is runnable with different inputs later.

### 4.2 Write the Dockerfile

- Pin a base (`alpine:3.20`, `python:3.13-slim`, `debian:bookworm-slim`).
- Install only what the tool needs; keep it small.
- Run as **non-root** by default; only elevate when the tool genuinely needs host/system
  access (and say why in the README).

```dockerfile
FROM alpine:3.20
RUN apk add --no-cache bash coreutils
COPY src/tool.sh /usr/local/bin/tool.sh
RUN chmod +x /usr/local/bin/tool.sh
ENTRYPOINT ["bash", "/usr/local/bin/tool.sh"]
```

### 4.3 Declare the manifest (the contract)

Only what the tool needs. Reads `/sys`? Mount it `:ro`. Must reach localhost services?
`network = "host"` (rare — prefer `bridge` + reachable service where possible).

Declare every parameter as a **typed input** in `[run.inputs]` (string/int/float/bool/enum,
mapped via `flag`/`env`/`positional`, with `default`/`required`). The runner rejects
unknown flags, missing required values, and type/enum mismatches **before** Docker starts —
so the manifest is the tool's CLI contract, not a suggestion. Check it with
`mischiefbox describe <tool>`.

### 4.4 Build, publish, test

```sh
cd ~/mischiefbox/tools/<tool>
docker build -t TheBarracks:3010/mischiefbox/<tool>:<version> .
docker push TheBarracks:3010/mischiefbox/<tool>:<version>

# test exactly as the runner will run it:
docker run --rm [--network host] [-v ...] TheBarracks:3010/mischiefbox/<tool>:<version> --help
docker run --rm [--network host] [-v ...] TheBarracks:3010/mischiefbox/<tool>:<version> --dry-run
```

Sanity-check against the manifest's own `[runtime]` — that **is** the definition of the
sandbox. Never smoke-test a mutating tool by running its real logic (use `--dry-run`).

### 4.5 Version & commit

- Bump `[meta].version` on behavior change; re-tag the image with the same version.
- Commit `tool.toml`, `Dockerfile`, `src/`, `README.md` together.
- `:latest` is for iteration; **named versions** are the source of truth for production.

### 4.6 Publish + discover (V0.5)

1. **Create the repo** (`POST /orgs/mischiefbox/repos`). The discovery token is
   **read-only** and cannot create repos — mint a short-lived write token with basic
   auth from the admin pass instead (see `ai-notes` 2026-08-19, `create-repos.sh`
   pattern).
2. Push the repo to the Gitea org (a repo with `tool.toml` **is** a tool). The push
   SSH key must be registered (`git push` → `publickey` otherwise); `refresh`'s clone
   uses the deploy key `~/mischiefbox/.ssh/id_ed25519`.
3. Build + push the image to the registry.
4. `mischiefbox refresh` — the runner re-scans the org and registers it. No manual
   `registry.toml` edits.

New tools appear in `mischiefbox list` automatically. The discovery token lives in
`~/mischiefbox/secrets/gitea-discovery-token` (gitignored; set with
`mischiefbox token <sha1>`).

## 5. Security & least privilege

- **Default deny:** no network, no privilege, read-only mounts.
- Add access only when the tool's job requires it; document why in the README.
- Mount the **narrowest path** — never the whole tree when one subdir suffices.
- **No secrets in images or repos.** A leaked token in an old script is debt, not a
  pattern to copy.
- **`[capabilities]` is the security contract (V0.4).** Declare the *maximum* the tool
  may use; `[runtime]` requests the actual values. The runner (CLI and API) **refuses to
  start** any container whose runtime exceeds the declared capabilities: network level,
  `privileged`/`pid=host`, and every mount under a declared root. A manifest with no
  `[capabilities]` is treated as defaults (none); write the block explicitly for every
  new tool. `mischiefbox describe <tool>` shows it.

## 6. Remote actions on Windows: GUI apps need a scheduled task

Tools that reach a Windows host over SSH and try to launch a **GUI app** will not work
with `start <app>`. SSH sessions are non-interactive: the process spawns into a session
that dies with the connection (and is invisible on the desktop anyway).

Working pattern (used by `open-notepad`): create + run a one-shot scheduled task with the
**interactive** flag (`/it`), so it lands in the logged-on user's desktop session:

```sh
schtasks /create /tn mb-open-notepad /tr notepad.exe /sc once /st 23:59 /it /f \
  && schtasks /run /tn mb-open-notepad
```

Notes:

- The task stays registered after running; re-creating with `/f` is fine (idempotent).
- Prefer a unique task name per tool (`mb-<tool>`).
- This applies to *any* interactive-session action (GUI apps, apps needing the user
  token), not just notepad. Non-GUI/headless commands over SSH work as-is.
- Windows OpenSSH + admin users: the public key goes in
  `C:\ProgramData\ssh\administrators_authorized_keys` (not `.ssh/authorized_keys`) —
  see `ai-notes`.
- **`schtasks /tr` is capped at 261 chars** — keep the actual logic in a helper script
  on the RIG (`C:\Users\<user>\mischiefbox-helpers\*.ps1`) and invoke it with
  `powershell -File ... -Arg val`.
- **Each SchTasks run steals focus** — a tool that types (e.g. `key-writer`) must focus
  the target window *in the same task*, not rely on a previous `get-focus` task.
- **`WScript.Shell.AppActivate` fails under SchTasks** — use `SetForegroundWindow`
  (P/Invoke) instead (see `get-focus`).
- **Per-keystroke `SendKeys` drops chars** on Win11 apps (uppercase/shift chars are
  worst). Use clipboard paste (`Set-Clipboard` + `SendKeys('^v')`) for reliable text
  entry (see `key-writer`).
- Window-focus targets: `Get-Process <name> | Sort StartTime -Descending` = "last
  opened". Strip `.exe` for `Get-Process`.
- **GUI apps load slowly** — don't focus immediately after launch. `get-focus` and
  `key-writer` poll for the process window up to `--wait` seconds (default 20) before
  failing, so a slow first load doesn't drop the keystrokes. Pass a longer `--wait` if
  an app takes unusually long.

## 7. HTTP API (V0.3)

`mischiefbox-api` (stdlib, threaded) listens on **127.0.0.1:8731** as a systemd service
(`mischiefbox-api.service`, auto-started). All responses are JSON.

| Endpoint | Notes |
|---|---|
| `GET /tools` | list `[{name, version, description}]` |
| `GET /tools/{name}` | full schema: image, inputs, outputs |
| `POST /tools/{name}/run` | body `{"args": [...], "print": bool}` → `{ok, exit_code, command, stdout, stderr}` |
| `POST /tools/{name}/install` | pull the image |
| `POST /refresh` | re-discover tools from the Gitea org (V0.5) → `{ok, tools}` |
| `GET /pipelines` | list pipelines (V0.6) |
| `POST /pipelines/{name}/run` | body `{"args": [...], "print": bool}` → `{ok, exit_code, steps}` |

Errors: 400 invalid inputs, 404 unknown tool/route, 500 docker unavailable.

- Input validation runs **server-side** (same `mischiefboxlib` the CLI uses), so callers
  can't bypass it. Output is rendered per `[run.outputs]`.
- **Security:** bound to localhost only — the API runs tools that may be privileged and
  see host mounts. Do not expose it publicly without auth (not yet implemented).
- CLI: `mischiefbox --api http://127.0.0.1:8731 <cmd>` or `$MB_API` env var forwards to
  the API; without it the CLI runs docker directly (same behavior, both modes).

## 8. Versioning & lifecycle

- Image tag == `[meta].version`. `latest` is a convenience pointer.
- Keep `src/` and the image in lockstep: a change to the code means a new build + tag.
- Repos and images are immutable history; rolling back = pointing at an older tag.

## 9. Legacy migration note

The 7 original host scripts (backup, power-monitor, battery-alert, qb-mover, jd-mover,
verify, jd-myjd-login) were retrofitted into Docker with `runtime = host`/privileged +
wide mounts to match their old behavior. **They are not the reference design.** Use
this guide for anything new; migrate the legacy tools toward it (narrow mounts, typed
inputs, `--dry-run`) as they're touched.

## 10. Pipelines (V0.6)

Pipelines compose tools into a linear, fail-fast chain. A pipeline is a
`pipeline.toml` under `~/mischiefbox/pipelines/<name>/` on TheBarracks.

```
[meta]
name = "write-new-notepad"
version = "0.1.0"
description = "open a new notepad on TheRisenKingdom and type a message"

[meta.inputs.message]      # optional pipeline-level params (same types as tool inputs)
type = "string"
required = true

[[steps]]                  # ordered steps; each is one tool invocation
tool = "open-notepad"
args = ["--new"]

[[steps]]
tool = "get-focus"
args = ["--process", "notepad.exe", "--last"]

[[steps]]
tool = "key-writer"
args = ["--message", "{{message}}", "--noquotes"]   # {{input}} interpolation
```

Rules & notes:
- Run: `mischiefbox pipeline <name> --key value` (or `mischiefbox run pipeline <name> ...`).
  List: `mischiefbox pipeline list`. API: `GET /pipelines`, `POST /pipelines/{name}/run`
  (body `{"args": ["--message", "..."]}`).
- Steps run **sequentially, fail-fast** — the first non-zero exit aborts the pipeline.
- Step `args` may reference pipeline inputs via `{{name}}` placeholders.
- Tools referenced must exist in the registry (discovered by `refresh`).
- Pipelines live in `~/mischiefbox/pipelines/` (not yet a repo/discoverable — plain files
  for now).

## 11. MCP adapter (V0.7)

MischiefBox exposes its tools as an **MCP server adapter** — a thin translation
layer only; the internal model is never exposed. Run it as a stdio subprocess
from any MCP client (e.g. Bunny Hole / agents).

- Binary: `~/.local/bin/mischiefbox-mcp` (symlink to `~/mischiefbox/mischiefbox-mcp`,
  stdlib-only Python). Test locally:
  `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' | ~/.local/bin/mischiefbox-mcp`.
- Transport: **stdio**, newline-delimited JSON-RPC 2.0 (one request per line, no
  Content-Length framing). Stderr is left free for the CLI/runner.
- Methods: `initialize`, `notifications/initialized`, `notifications/cancelled`
  (no reply), `ping`, `resources/list`, `resources/templates/list`,
  `resources/read`, `tools/list`, `tools/call`, `shutdown`.
- **Resources (authoring context, V0.7.1):** the docs are exposed as readable
  MCP resources so any client can pull the authoring contract on demand, not just
  the runtime schemas. URIs: `mischiefbox://docs/mischiefbox-dev-guide`,
  `mischiefbox://docs/plan`, `mischiefbox://docs/ai-notes` — read from
  `~/Documents/ai-notes/` on TheBarracks (`text/markdown`).
- Protocol negotiation: supports `2024-11-05`, `2025-03-26`, `2025-06-18`; echoes
  back the requested version, defaults to `2024-11-05`. Reply always carries
  `capabilities.tools.listChanged = false` and `serverInfo`.
- `tools/list` builds JSON Schema from `[run.inputs]`: `string`→`string`,
  `int`→`integer`, `float`→`number`, `bool`→`boolean`, `enum`→`string` +
  `enum` array; `required`/`default`/`description` carried over.
- `tools/call` converts the arguments dict to CLI args (`--key value`; bool →
  `--key=true/false`), runs the tool through the same docker runner as the CLI,
  returns `content[0].text` (rendered output) and `isError = (exit != 0)`.
- Errors: standard JSON-RPC codes — `-32700` parse, `-32600` invalid request,
  `-32601` method not found, `-32602` invalid params (unknown tool / missing or
  invalid input), `-32603` internal.

## 12. Development pitfalls

### 12.1 Windows SSH key permissions

When mounting SSH keys from Windows (`C:\Users\...\.ssh`) into Linux containers, the
mount preserves Windows permissions (0777). SSH refuses to use keys with lax permissions:

```
Permissions 0777 for '/root/.ssh/id_ed25519' are too open.
```

**Fix:** Copy the key to a writable location inside the container and chmod it:

```bash
mkdir -p /tmp/.ssh
cp /root/.ssh/id_ed25519 /tmp/.ssh/id_ed25519
chmod 600 /tmp/.ssh/id_ed25519
SSH_OPTS="${SSH_OPTS} -i /tmp/.ssh/id_ed25519"
```

This works even with `:ro` mounts since you're copying, not modifying in place.

### 12.2 Input mapping requires `env`

Inputs declared in `tool.toml` are **not** automatically passed to the container. The
runner only forwards inputs that have an `env` mapping:

```toml
# WRONG — input is validated but never reaches the container
[run.inputs]
user_id = { type = "int", description = "User ID" }

# CORRECT — input is passed as USER_ID environment variable
[run.inputs]
user_id = { type = "int", env = "USER_ID", description = "User ID" }
```

Without `env`, the script sees an empty variable and fails silently or with a confusing
error. The `flag` and `positional` mappings work differently — `flag` adds CLI args
after the command, `positional` adds bare values in declaration order.

### 12.3 Python quoting in SSH commands

Embedding Python code with single quotes in SSH remote commands breaks the shell:

```bash
# BROKEN — Python's single quotes conflict with shell quoting
ssh host "python3 -c 'import sys; print(sys.argv[1])'"

# WORKING — use heredoc to pass script as stdin
ssh host bash <<'REMOTE_EOF'
python3 <<'PYEOF'
import sys
print(sys.argv[1])
PYEOF
REMOTE_EOF
```

For complex scripts, write to a temp file first:

```bash
ssh host "cat > /tmp/script.py" <<'PYEOF'
import sys
# ... complex code with mixed quotes ...
PYEOF
ssh host "python3 /tmp/script.py arg1 arg2"
```

### 12.4 Remote services may run in containers

When SSHing to a server, the target service might be in a Docker container. You can't
run commands directly — you need `docker exec`:

```bash
# BROKEN — Odoo isn't installed on the host
ssh root@server "python3 -c 'import odoo'"

# WORKING — execute inside the container
ssh root@server "docker exec main-odoo-web-1 python3 -c 'import odoo'"
```

Check with `docker ps` on the remote host to find the container name.

### 12.5 Alpine SSH first-connection warnings

Alpine containers don't have a known_hosts file by default. First SSH connections
trigger a host key warning. Add these options to suppress it in tool scripts:

```bash
SSH_OPTS="-o ConnectTimeout=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

For production tools, consider pinning the host key via mount instead of disabling
verification.

### 12.6 READ-ONLY mounts prevent chmod

You cannot `chmod` files on a read-only mount (`:ro`). If you need to fix permissions
(e.g. SSH keys from Windows), copy the file to a writable location first:

```bash
# This fails on :ro mounts
chmod 600 /root/.ssh/id_ed25519  # Permission denied

# This works — copy then chmod
cp /root/.ssh/id_ed25519 /tmp/.ssh/id_ed25519
chmod 600 /tmp/.ssh/id_ed25519
```

## 13. Run history logging (V0.8 — planned)

MischiefBox currently has **no persistent run history**. Tool containers are ephemeral
(`--rm`) and their stdout/stderr is lost after execution. The API service only logs
its startup message.

### 13.1 Current state

- Tool runs: stdout/stderr → terminal/API response → gone
- API service: logs startup to `api.log` and systemd journal
- No record of what tools were run, when, or with what parameters

### 13.2 Proposed solution

Add run history logging at the **CLI/API layer** (not in individual tools):

1. **Log file:** `~/mischiefbox/runs.log` (append-only, JSONL format)
2. **Each entry:**
   ```json
   {
     "ts": "2026-08-20T14:30:00-03:00",
     "tool": "open-notepad",
     "args": ["--new"],
     "exit_code": 0,
     "stdout_preview": "...",
     "stderr_preview": "...",
     "duration_ms": 1234,
     "source": "cli|api|mcp"
   }
   ```
3. **CLI integration:** `mischiefbox run <tool>` appends to `runs.log` after execution
4. **API integration:** `POST /tools/{name}/run` appends to `runs.log`
5. **New command:** `mischiefbox history [--tool <name>] [--last <n>]` to view recent runs
6. **API endpoint:** `GET /history?tool=<name>&last=<n>` for remote access

### 13.3 Implementation notes

- Log before docker run (with `running` state) and after (with result)
- Rotate logs at 10MB (keep last 5 files)
- Sensitive args (tokens, passwords) should be redacted in logs
- Consider adding `--no-log` flag for privacy-sensitive runs