#!/bin/bash
set -euo pipefail

QUERY="${QUERY:-}"
SOURCE="${SOURCE:-all}"
MODULE="${MODULE:-}"
LIMIT="${LIMIT:-30}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "query is required"}'
    exit 1
fi

PATHS=()
case "$SOURCE" in
    community) PATHS+=("/odoo/community/odoo/addons" "/odoo/community/odoo/odoo") ;;
    enterprise) PATHS+=("/odoo/enterprise") ;;
    saas) PATHS+=("/odoo/saas/addons") ;;
    all) PATHS+=("/odoo/community/odoo/addons" "/odoo/community/odoo/odoo" "/odoo/enterprise" "/odoo/saas/addons") ;;
esac

if [[ -n "$MODULE" ]]; then
    NEW_PATHS=()
    for p in "${PATHS[@]}"; do
        [[ -d "$p/$MODULE" ]] && NEW_PATHS+=("$p/$MODULE")
    done
    PATHS=("${NEW_PATHS[@]:-}")
fi

TEMP_FILE=$(mktemp)
for p in "${PATHS[@]}"; do
    [[ -d "$p" ]] || continue
    grep -r -n \
        --include="*.py" --include="*.xml" --include="*.csv" \
        --exclude-dir=".git" --exclude-dir="__pycache__" \
        "$QUERY" "$p" 2>/dev/null >> "$TEMP_FILE" || true
done

TOTAL=$(wc -l < "$TEMP_FILE" | tr -d ' ')
if [[ "$TOTAL" -eq 0 ]]; then
    echo '{"count": 0, "results": []}'
    rm -f "$TEMP_FILE"
    exit 0
fi

head -n "$LIMIT" "$TEMP_FILE" | python3 -c "
import json, sys, re
from collections import OrderedDict

results = OrderedDict()
for line in sys.stdin:
    line = line.rstrip()
    m = re.match(r'^(.+?):(\d+):(.*)$', line)
    if not m:
        continue
    f = re.sub(r'^/odoo/(community|enterprise|saas)/', r'\1/', m.group(1))
    if f not in results:
        results[f] = []
    results[f].append({'line': int(m.group(2)), 'content': m.group(3).strip()[:200]})

out = [{'file': k, 'matches': v[:10]} for k, v in results.items()]
print(json.dumps({'count': len(out), 'results': out}, indent=2))
"

rm -f "$TEMP_FILE"
