#!/usr/bin/env bash
# docker-health - Show Docker container status and resource usage
set -euo pipefail

FILTER=""
ALL=false

usage() {
  echo "Usage: docker-health [--filter NAME] [--all]"
  echo ""
  echo "Show Docker container health and resource usage."
  echo ""
  echo "Options:"
  echo "  --filter NAME   Filter containers by name (partial match)"
  echo "  --all           Show all containers including stopped"
  echo "  --help          Show this help"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter) FILTER="$2"; shift 2 ;;
    --all) ALL=true; shift ;;
    --help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Build docker ps command
PS_ARGS="--format {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}\t{{.RunningFor}}"
if [ "$ALL" = true ]; then
  PS_ARGS="-a $PS_ARGS"
fi
if [ -n "$FILTER" ]; then
  PS_ARGS="$PS_ARGS --filter name=$FILTER"
fi

# Get container list
CONTAINERS=$(docker ps $PS_ARGS 2>/dev/null || echo "")

# Build JSON
echo "{"
echo "  \"containers\": ["

FIRST=true
while IFS=$'\t' read -r NAME STATUS IMAGE PORTS RUNNING_FOR; do
  [ -z "$NAME" ] && continue

  # Parse status for running state
  if echo "$STATUS" | grep -qi "up"; then
    RUNNING="true"
  else
    RUNNING="false"
  fi

  # Get stats for running containers
  CPU="0"
  MEM="0"
  MEM_PCT="0"
  NET_IO="0"
  BLOCK_IO="0"
  PIDS="0"

  if [ "$RUNNING" = "true" ]; then
    STATS=$(docker stats --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}" "$NAME" 2>/dev/null || echo "")
    if [ -n "$STATS" ]; then
      IFS=$'\t' read -r CPU MEM MEM_PCT NET_IO BLOCK_IO PIDS <<< "$STATS"
    fi
  fi

  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo ","
  fi

  # Escape quotes in values
  IMAGE=$(echo "$IMAGE" | sed 's/"/\\"/g')
  STATUS=$(echo "$STATUS" | sed 's/"/\\"/g')
  PORTS=$(echo "$PORTS" | sed 's/"/\\"/g')

  printf '    {"name": "%s", "running": %s, "status": "%s", "image": "%s", "ports": "%s", "uptime": "%s", "cpu": "%s", "mem": "%s", "mem_pct": "%s", "net_io": "%s", "block_io": "%s", "pids": "%s"}' \
    "$NAME" "$RUNNING" "$STATUS" "$IMAGE" "$PORTS" "$RUNNING_FOR" "$CPU" "$MEM" "$MEM_PCT" "$NET_IO" "$BLOCK_IO" "$PIDS"

done <<< "$CONTAINERS"

echo ""
echo "  ]"
echo "}"
