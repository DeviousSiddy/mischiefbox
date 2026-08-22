#!/usr/bin/env bash
# lan-devices - Scan LAN for active devices
set -euo pipefail

SUBNET="192.168.100.0/24"
TIMEOUT=2

usage() {
  echo "Usage: lan-devices [--subnet CIDR] [--timeout SECS]"
  echo ""
  echo "Scan the local network for active devices."
  echo ""
  echo "Options:"
  echo "  --subnet CIDR    Subnet to scan (default: 192.168.100.0/24)"
  echo "  --timeout SECS   Ping timeout per host in seconds (default: 2)"
  echo "  --help           Show this help"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subnet) SUBNET="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Extract network prefix (e.g., 192.168.100)
NETWORK=$(echo "$SUBNET" | cut -d'.' -f1-3)

# Get own IP to skip
MY_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")

echo "{"
echo "  \"subnet\": \"$SUBNET\","
echo "  \"devices\": ["

FIRST=true
for i in $(seq 1 254); do
  IP="${NETWORK}.${i}"
  [ "$IP" = "$MY_IP" ] && continue

  # Quick ping with short timeout
  if ping -c 1 -W "$TIMEOUT" "$IP" >/dev/null 2>&1; then
    # Try to get MAC from ARP table
    MAC=$(ip neigh show "$IP" 2>/dev/null | awk '/lladdr/ {print $5}' || echo "")
    # Try to get hostname
    HOSTNAME=$(getent hosts "$IP" 2>/dev/null | awk '{print $2}' || echo "")

    if [ "$FIRST" = true ]; then
      FIRST=false
    else
      echo ","
    fi
    printf '    {"ip": "%s", "mac": "%s", "hostname": "%s"}' "$IP" "$MAC" "$HOSTNAME"
  fi
done

echo ""
echo "  ]"
echo "}"
