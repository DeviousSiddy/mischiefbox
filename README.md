# MischiefBox

A self-contained tool runner that executes parameterized Docker containers via a CLI, HTTP API, or MCP adapter.

## What's Included

- **CLI** (`mischiefbox` / `mb`) - Run tools directly from the command line
- **HTTP API** (`mischiefbox-api`) - REST API for running tools remotely
- **MCP Adapter** (`mischiefbox-mcp`) - Model Context Protocol adapter for AI assistants
- **Gitea** - Self-hosted Git server for tool repository management
- **Example Pipeline** - A 3-step pipeline to type text into notepad

## Prerequisites

- Linux (Debian/Ubuntu recommended) or WSL2 on Windows
- Docker 20.10+
- Python 3.11+
- sudo access

## Quick Install

### Native Linux

```bash
git clone https://github.com/DeviousSiddy/mischiefbox.git
cd mischiefbox
sudo ./install.sh
```

### WSL2 (Windows Subsystem for Linux)

1. **Install WSL2** (if not already installed):
   ```powershell
   wsl --install
   ```
   Restart your computer after installation.

2. **Install Docker Desktop for Windows** with WSL2 integration enabled:
   - Download from [docker.com](https://www.docker.com/products/docker-desktop/)
   - In Settings > Resources > WSL Integration, enable your Ubuntu distribution

3. **Run the installer from PowerShell**:
   ```powershell
   git clone https://github.com/DeviousSiddy/mischiefbox.git
   cd mischiefbox
   wsl bash -c "sudo ./install.sh"
   ```

4. **Access from Windows**:
   - Gitea: `http://localhost:3010`
   - API: `http://localhost:8731`
   - Tools run inside WSL's Docker, accessible from Windows apps

> **Note:** WSL2 automatically forwards ports from the Linux VM to Windows, so you can access Gitea and the API from Windows browsers and tools.

## Post-Install Setup

### 1. Start Gitea

**Native Linux:**
```bash
cd /opt/mischiefbox/gitea
docker compose up -d
```

**WSL2:**
```powershell
wsl bash -c "cd /opt/mischiefbox/gitea && sudo docker compose up -d"
```

### 2. Complete Gitea Setup

Open `http://localhost:3010` in your browser and:
- Create an admin account
- Create an organization named `mischiefbox`
- Enable package registry (Settings > Packages)

### 3. Configure MischiefBox

First, create a Gitea API token:
1. In Gitea, go to Settings > Applications > Create Token
2. Select scopes: `read:organization`, `read:repository`, `write:repository`, `write:organization`
3. Copy the generated token

**Native Linux:**
```bash
mischiefbox token <your-gitea-token>
```

**WSL2:**
```powershell
wsl bash -c "mb token <your-gitea-token>"
```

### 4. Start the API Server

**Native Linux:**
```bash
systemctl start mischiefbox-api
systemctl status mischiefbox-api
```

**WSL2** (systemd may not be available - run manually instead):
```powershell
# Option A: Run in background
wsl bash -c "nohup mb-api > /tmp/mischiefbox-api.log 2>&1 &"

# Option B: Run in foreground (Ctrl+C to stop)
wsl bash -c "mb-api"
```

> **Note:** WSL2 may not have systemd enabled. If `systemctl` fails, use the manual method above. To enable systemd in WSL, add `[boot] systemd=true` to `/etc/wsl.conf` and restart WSL.

### 5. Create/Discover Tools

**Native Linux:**
```bash
mischiefbox refresh
mischiefbox list
```

**WSL2:**
```powershell
wsl bash -c "mb refresh"
wsl bash -c "mb list"
```

## Usage

### CLI

```bash
# List tools
mischiefbox list

# Describe a tool
mischiefbox describe <tool-name>

# Run a tool
mischiefbox run <tool-name> [--args...]

# Run via API
mischiefbox --api http://localhost:8731 run <tool-name> [--args...]

# Pipelines
mischiefbox pipeline list
mischiefbox pipeline <name> --key value

# View run history
mischiefbox history                    # show last 20 runs
mischiefbox history --tool <name>      # filter by tool
mischiefbox history --last 5           # show last 5 runs
```

### HTTP API

```bash
# List tools
curl http://localhost:8731/tools

# Run a tool
curl -X POST http://localhost:8731/tools/<tool-name>/run \
  -H "Content-Type: application/json" \
  -d '{"args": ["--key", "value"]}'

# List pipelines
curl http://localhost:8731/pipelines

# Run a pipeline
curl -X POST http://localhost:8731/pipelines/<name>/run \
  -H "Content-Type: application/json" \
  -d '{"args": ["--message", "Hello World"]}'

# View run history
curl http://localhost:8731/history
curl "http://localhost:8731/history?tool=<name>&last=10"
```

### MCP Adapter

The MCP adapter exposes MischiefBox tools to AI assistants like Claude Desktop, Bunny Hole, Cursor, etc.

#### Verify MCP is working

```powershell
# Test the MCP adapter (should return server info JSON)
wsl bash -c "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\"}}' | /opt/mischiefbox/bin/mischiefbox-mcp"
```

#### Claude Desktop Configuration

Add to your Claude Desktop config file:
- **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`

**Native Linux:**
```json
{
  "mcpServers": {
    "mischiefbox": {
      "command": "/usr/local/bin/mb-mcp"
    }
  }
}
```

**WSL2:**
```json
{
  "mcpServers": {
    "mischiefbox": {
      "command": "wsl",
      "args": ["bash", "-c", "/opt/mischiefbox/bin/mischiefbox-mcp"]
    }
  }
}
```

#### Cursor / Windsurf Configuration

Add to your MCP settings (`.cursor/mcp.json` or similar):

**Native Linux:**
```json
{
  "mcpServers": {
    "mischiefbox": {
      "command": "/usr/local/bin/mb-mcp"
    }
  }
}
```

**WSL2:**
```json
{
  "mcpServers": {
    "mischiefbox": {
      "command": "wsl",
      "args": ["bash", "-c", "/opt/mischiefbox/bin/mischiefbox-mcp"]
    }
  }
}
```

#### Bunny Hole / OpenCode Configuration

Add to your MCP server config:

**Native Linux:**
```json
{
  "mcpServers": {
    "mischiefbox": {
      "command": "/usr/local/bin/mb-mcp"
    }
  }
}
```

**WSL2:**
```json
{
  "mcpServers": {
    "mischiefbox": {
      "command": "wsl",
      "args": ["bash", "-c", "/opt/mischiefbox/bin/mischiefbox-mcp"]
    }
  }
}
```

#### OpenCode Configuration

OpenCode uses a different config format. Add to `~/.config/opencode/opencode.json`:

**Native Linux:**
```json
{
  "mcp": {
    "mischiefbox": {
      "type": "local",
      "command": ["/usr/local/bin/mb-mcp"],
      "enabled": true
    }
  }
}
```

**WSL2:**
```json
{
  "mcp": {
    "mischiefbox": {
      "type": "local",
      "command": ["wsl", "bash", "-c", "/opt/mischiefbox/bin/mischiefbox-mcp"],
      "enabled": true
    }
  }
}
```

If tools don't appear after restart, add `"tools": { "mischiefbox_*": true }` to the config. See [docs/opencode-mcp-setup.md](docs/opencode-mcp-setup.md) for the full guide.

#### What the MCP provides

Once connected, the AI assistant can:
- **List tools:** See all available MischiefBox tools
- **Call tools:** Execute tools with parameters (e.g., "run ntfy-send with topic=test and message=hello")
- **Read resources:** Access MischiefBox documentation for context

**Available tools (examples):**
- `ntfy-send` - Send notifications
- `open-notepad` - Open notepad on Windows
- `key-writer` - Type text into focused window
- `get-focus` - Focus a process window
- `ssh-alias` - Read SSH config
- `net-check` - Check internet connectivity

**Note:** Pipelines are not exposed via MCP. To run a pipeline, use the CLI:
```powershell
wsl bash -c "mb pipeline <name> --key value"
```

## Configuration

Configuration is via environment variables or `/opt/mischiefbox/.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `MB_HOME` | `/opt/mischiefbox` | MischiefBox home directory |
| `MB_GITEA_URL` | `http://localhost:3010` | Gitea API URL |
| `MB_GITEA_SSH_HOST` | `localhost` | Gitea SSH hostname (for git clones) |
| `MB_GITEA_SSH_PORT` | `3022` | Gitea SSH port |
| `MB_GITEA_ORG` | `mischiefbox` | Gitea organization name |
| `MB_API_HOST` | `127.0.0.1` | API bind address |
| `MB_API_PORT` | `8731` | API port |

## Creating Tools

Tools are Docker containers with a `tool.toml` manifest:

```toml
[meta]
name = "my-tool"
version = "0.1.0"
description = "Does something useful"

[run]
image = "my-tool:0.1.0"
command = ["/usr/local/bin/my-tool"]

[run.inputs]
name = { type = "string", required = true, description = "Input name" }
verbose = { type = "bool", flag = "--verbose", default = false }

[runtime]
network = "none"
```

See [MischiefBox Documentation](https://github.com/DeviousSiddy/mischiefbox/blob/main/docs/mischiefbox-dev-guide.md) for the full tool authoring contract.

## Example Pipeline

The installer includes a `write-new-notepad` pipeline:

```toml
[meta]
name = "write-new-notepad"
version = "0.1.0"
description = "open a new notepad window and type a message"

[meta.inputs.message]
type = "string"
required = true

[[steps]]
tool = "open-notepad"
args = ["--new"]

[[steps]]
tool = "get-focus"
args = ["--process", "notepad.exe", "--last"]

[[steps]]
tool = "key-writer"
args = ["--message", "{{message}}", "--noquotes"]
```

Run it:
```bash
mischiefbox pipeline write-new-notepad --message "Hello World"
```

## Directory Structure

```
/opt/mischiefbox/
├── bin/                    # Python scripts + helpers
│   ├── mischiefbox         # CLI
│   ├── mischiefboxlib.py   # Core library
│   ├── mischiefbox-api     # HTTP API
│   ├── mischiefbox-mcp     # MCP adapter
│   ├── mb                  # CLI wrapper
│   ├── mb-api              # API wrapper
│   └── mb-mcp              # MCP wrapper
├── gitea/                  # Gitea docker-compose
├── tools/                  # Cloned tool repositories
├── pipelines/              # Pipeline definitions
├── secrets/                # Tokens and keys (gitignored)
├── .ssh/                   # Deploy key
├── .env                    # Configuration
└── registry.toml           # Auto-generated tool registry
```

## Uninstall

```bash
sudo systemctl stop mischiefbox-api
sudo systemctl disable mischiefbox-api
sudo rm /etc/systemd/system/mischiefbox-api.service
sudo rm -rf /opt/mischiefbox
sudo rm /usr/local/bin/mb /usr/local/bin/mb-api /usr/local/bin/mb-mcp
```

## License

MIT
