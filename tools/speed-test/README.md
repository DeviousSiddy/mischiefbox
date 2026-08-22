# speed-test

Test internet download speed.

## Usage

```bash
mischiefbox run speed-test                    # 10MB test
mischiefbox run speed-test --size 50          # 50MB test
mischiefbox run speed-test --server http://speedtest.net
```

## Output

JSON with download speed (Mbps), test size, server, and latency.

## Runtime

Requires `network = host` for internet access.
