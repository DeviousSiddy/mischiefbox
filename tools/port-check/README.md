# port-check

Test if a TCP port is open on a host.

## Usage

```bash
mischiefbox run port-check --host 192.168.100.207 --port 22
mischiefbox run port-check --host google.com --port 443 --timeout 5
```

## Output

JSON with host, port, open (boolean), and latency_ms.

## Runtime

Requires `network = host` for TCP connections.
