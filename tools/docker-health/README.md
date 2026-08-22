# docker-health

Show Docker container status and resource usage.

## Usage

```bash
mischiefbox run docker-health                      # all running containers
mischiefbox run docker-health --all                # include stopped
mischiefbox run docker-health --filter gitea       # filter by name
```

## Output

JSON with list of containers including name, status, image, ports, uptime, and resource usage (CPU, memory, network I/O).

## Runtime

Requires Docker socket mounted read-only. Runs without privilege.
