#!/usr/bin/env bash
# speed-test - Test internet download speed
set -euo pipefail

SIZE_MB=10
SERVER="http://speedtest.tele2.net"

usage() {
  echo "Usage: speed-test [--size MB] [--server URL]"
  echo ""
  echo "Test internet download speed."
  echo ""
  echo "Options:"
  echo "  --size MB      Download size in MB (default: 10)"
  echo "  --server URL   Test server base URL (default: speedtest.tele2.net)"
  echo "  --help         Show this help"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --size) SIZE_MB="$2"; shift 2 ;;
    --server) SERVER="$2"; shift 2 ;;
    --help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Test URL
TEST_URL="${SERVER}/${SIZE_MB}MB.zip"

# Measure download speed
START=$(date +%s%N)
curl -s -o /dev/null -w "%{speed_download}" "$TEST_URL" 2>/dev/null
END=$(date +%s%N)

# Get speed from curl (bytes per second)
SPEED_BPS=$(curl -s -o /dev/null -w "%{speed_download}" "$TEST_URL" 2>/dev/null)

# Convert to Mbps
SPEED_MBPS=$(echo "scale=2; $SPEED_BPS * 8 / 1000000" | bc 2>/dev/null || echo "0")

# Also get latency to the server
LATENCY_MS=$(curl -s -o /dev/null -w "%{time_starttransfer}" --connect-timeout 5 "$SERVER" 2>/dev/null | awk '{printf "%.0f", $1 * 1000}' || echo "0")

echo "{"
echo "  \"download_mbps\": $SPEED_MBPS,"
echo "  \"download_bytes_per_sec\": $SPEED_BPS,"
echo "  \"test_size_mb\": $SIZE_MB,"
echo "  \"server\": \"$SERVER\","
echo "  \"latency_ms\": $LATENCY_MS"
echo "}"
