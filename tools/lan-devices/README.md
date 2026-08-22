# lan-devices

Scan the local network for active devices using ICMP ping sweeps.

## Usage

```bash
mischiefbox run lan-devices                           # scan default subnet
mischiefbox run lan-devices --subnet 192.168.1.0/24   # scan custom subnet
mischiefbox run lan-devices --timeout 1               # faster scan
```

## Output

JSON with list of discovered devices (IP, MAC, hostname).

## Runtime

Requires `network = host` for ARP lookups and ping sweeps.
