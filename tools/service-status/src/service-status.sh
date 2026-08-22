#!/usr/bin/env bash
# service-status - Check systemd service status
set -euo pipefail

SERVICE=""
HOST=""
SSH_USER=""
SSH_KEY=""
LOCAL=true

usage() {
  echo "Usage: service-status --service NAME [--host HOST] [--ssh-user USER] [--ssh-key KEY]"
  echo ""
  echo "Check the status of a systemd service."
  echo ""
  echo "Options:"
  echo "  --service NAME   Service name (required)"
  echo "  --host HOST      SSH host for remote check"
  echo "  --ssh-user USER  SSH user (default: root)"
  echo "  --ssh-key KEY    Path to SSH key"
  echo "  --help           Show this help"
  echo ""
  echo "Examples:"
  echo "  service-status --service docker"
  echo "  service-status --service ntfy --host 192.168.100.60 --ssh-user devioussiddy"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service) SERVICE="$2"; shift 2 ;;
    --host) HOST="$2"; LOCAL=false; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [ -z "$SERVICE" ]; then
  echo '{"error": "--service is required"}'
  exit 1
fi

# Build SSH command if remote
if [ "$LOCAL" = false ]; then
  SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  [ -n "$SSH_USER" ] && SSH_CMD="$SSH_CMD $SSH_USER@$HOST" || SSH_CMD="$SSH_CMD $HOST"
  [ -n "$SSH_KEY" ] && SSH_CMD="$SSH_CMD -i $SSH_KEY"
else
  SSH_CMD=""
fi

# Get service status
if [ "$LOCAL" = true ]; then
  STATUS_JSON=$(systemctl show "$SERVICE" --property=ActiveState,SubState,ActiveEnterTimestamp,ExecMainPID --json 2>/dev/null || echo '{"ActiveState":"unknown","SubState":"unknown","ActiveEnterTimestamp":"","ExecMainPID":0}')
else
  STATUS_JSON=$($SSH_CMD "systemctl show $SERVICE --property=ActiveState,SubState,ActiveEnterTimestamp,ExecMainPID --json" 2>/dev/null || echo '{"ActiveState":"unknown","SubState":"unknown","ActiveEnterTimestamp":"","ExecMainPID":0}')
fi

# Parse JSON
ACTIVE=$(echo "$STATUS_JSON" | grep -o '"ActiveState":"[^"]*"' | cut -d'"' -f4)
SUB=$(echo "$STATUS_JSON" | grep -o '"SubState":"[^"]*"' | cut -d'"' -f4)
SINCE=$(echo "$STATUS_JSON" | grep -o '"ActiveEnterTimestamp":"[^"]*"' | cut -d'"' -f4)
PID=$(echo "$STATUS_JSON" | grep -o '"ExecMainPID":[0-9]*' | cut -d: -f2)

# Determine running
if [ "$ACTIVE" = "active" ]; then
  RUNNING="true"
else
  RUNNING="false"
fi

echo "{"
echo "  \"service\": \"$SERVICE\","
echo "  \"running\": $RUNNING,"
echo "  \"active_state\": \"$ACTIVE\","
echo "  \"sub_state\": \"$SUB\","
echo "  \"since\": \"$SINCE\","
echo "  \"pid\": $PID,"
echo "  \"remote\": $([ "$LOCAL" = false ] && echo "true" || echo "false")"
echo "}"
