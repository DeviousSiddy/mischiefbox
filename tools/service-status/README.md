# service-status

Check systemd service status on local or remote hosts.

## Usage

```bash
mischiefbox run service-status --service docker
mischiefbox run service-status --service ntfy --host 192.168.100.60 --ssh-user devioussiddy
```

## Output

JSON with service name, running (boolean), active/sub state, since timestamp, PID, and whether it's remote.

## Runtime

Requires `network = host` for SSH connections. Mount SSH keys at `/key`.
