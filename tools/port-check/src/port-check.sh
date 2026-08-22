#!/usr/bin/env bash
# port-check - Test if a TCP port is open
set -euo pipefail

HOST=""
PORT=""
TIMEOUT=3

usage() {
  echo "Usage: port-check --host HOST --port PORT [--timeout SECS]"
  echo ""
  echo "Test if a TCP port is open on a host."
  echo ""
  echo "Options:"
  echo "  --host HOST      Target host (required)"
  echo "  --port PORT      Target port (required)"
  echo "  --timeout SECS   Connection timeout (default: 3)"
  echo "  --help           Show this help"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [ -z "$HOST" ] || [ -z "$PORT" ]; then
  echo '{"error": "Both --host and --port are required"}'
  exit 1
fi

# Use nc (netcat) to test the port
START_MS=$(($(date +%s%N)/1000000))

if nc -z -w "$TIMEOUT" "$HOST" "$PORT" 2>/dev/null; then
  END_MS=$(($(date +%s%N)/1000000))
  LATENCY=$((END_MS - START_MS))
  echo "{\"host\": \"$HOST\", \"port\": $PORT, \"open\": true, \"latency_ms\": $LATENCY}"
else
  END_MS=$(($(date +%s%N)/1000000))
  LATENCY=$((END_MS - START_MS))
  echo "{\"host\": \"$HOST\", \"port\": $PORT, \"open\": false, \"latency_ms\": $LATENCY}"
fi
