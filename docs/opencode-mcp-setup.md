# MischiefBox — OpenCode MCP Setup

How to connect MischiefBox tools to [OpenCode](https://opencode.ai) via the Model Context Protocol.

## Prerequisites

- MischiefBox installed (`/opt/mischiefbox/bin/mischiefbox-mcp`)
- OpenCode installed (`opencode --version`)
- WSL2 with Docker Desktop (Windows) or native Linux

## Configuration

Add MischiefBox to your OpenCode config file (`~/.config/opencode/opencode.json`):

### Native Linux

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "mischiefbox": {
      "type": "local",
      "command": ["/usr/local/bin/mb-mcp"],
      "enabled": true
    }
  }
}
```

### WSL2 (Windows)

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "mischiefbox": {
      "type": "local",
      "command": ["wsl", "bash", "-c", "/opt/mischiefbox/bin/mischiefbox-mcp"],
      "enabled": true
    }
  }
}
```

### Enable tools explicitly (optional)

By default, MCP tools are available once the server connects. If tools don't appear, add the `tools` section:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "mischiefbox": {
      "type": "local",
      "command": ["wsl", "bash", "-c", "/opt/mischiefbox/bin/mischiefbox-mcp"],
      "enabled": true
    }
  },
  "tools": {
    "mischiefbox_*": true
  }
}
```

The `mischiefbox_*` glob pattern enables all tools from the MischiefBox server.

## Verify the connection

1. **Restart OpenCode** after editing the config
2. Check the MCP server status:
   ```bash
   opencode mcp list
   ```
   You should see `mischiefbox` with a `connected` status.

3. Test a tool in your prompt:
   ```
   use mischiefbox_odoo-db-query to run: SELECT id, login FROM res_users LIMIT 3
   ```

## Debugging

### Tools not appearing

1. Verify the server is connected:
   ```bash
   opencode mcp list
   ```

2. Check the resolved config:
   ```bash
   opencode debug config | Select-String mischiefbox
   ```

3. Test the MCP adapter directly:
   ```bash
   # Native Linux
   echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | /usr/local/bin/mb-mcp

   # WSL2
   wsl bash -c 'echo "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" | /opt/mischiefbox/bin/mischiefbox-mcp'
   ```

### OAuth debug (remote servers only)

```bash
opencode mcp debug mischiefbox
```

This only applies to remote MCP servers. Local servers (like MischiefBox) will show "not a remote server".

## Available tools

Once connected, the following tools are available:

| Tool | Description |
|------|-------------|
| `mischiefbox_<tool-name>` | Each tool from your MischiefBox registry is exposed as `mischiefbox_<name>` |

Tools are auto-discovered from the MischiefBox registry. Push new tool repos to Gitea and run `mischiefbox refresh` to make them available in OpenCode.

## Prompting tips

- Reference tools explicitly: `use the mischiefbox_odoo-db-query tool`
- Or add to your `AGENTS.md`:
  ```
  When you need to run MischiefBox tools, use the mischiefbox_* MCP tools.
  ```
