#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/}"
  printf '%s' "$value"
}

if ! command -v apt >/dev/null 2>&1; then
  printf '{"text":"Updates ?","tooltip":"apt is not available","class":["updates","error"],"percentage":100}\n'
  exit 0
fi

updates=$(apt list --upgradable 2>/dev/null || true)
if [[ -z "$updates" ]]; then
  printf '{"text":"Updates ?","tooltip":"Unable to read apt upgrade state","class":["updates","error"],"percentage":100}\n'
  exit 0
fi

updates_list="$(printf '%s\n' "$updates" | awk 'NR > 1 && NF { print }')"
count="$(printf '%s\n' "$updates_list" | awk 'NF { count++ } END { print count + 0 }')"

if (( count == 0 )); then
  text="Up to date"
  tooltip="System is up to date."
  class='["updates","up-to-date"]'
  percentage=0
else
  text="Updates ${count}"
  tooltip="$(printf '%s\n' "$updates_list" | sed -n '1,20p')"
  if (( count > 20 )); then
    tooltip="${tooltip}"$'\n'"... and $((count - 20)) more"
  fi
  if (( count >= 25 )); then
    class='["updates","critical"]'
    percentage=100
  elif (( count >= 10 )); then
    class='["updates","warning"]'
    percentage=60
  else
    class='["updates","pending"]'
    percentage=25
  fi
fi

printf '{"text":"%s","tooltip":"%s","class":%s,"percentage":%s}\n' \
  "$(json_escape "$text")" \
  "$(json_escape "$tooltip")" \
  "$class" \
  "$percentage"
