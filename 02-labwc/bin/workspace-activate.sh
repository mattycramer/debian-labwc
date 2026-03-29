#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

workspace="${1:-}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/debian-labwc"
state_file="$state_root/current-workspace"

case "$workspace" in
  1|2|3|4) ;;
  *) exit 1 ;;
esac

command -v /usr/local/bin/debian-labwc-workspacectl >/dev/null 2>&1 || exit 1
/usr/local/bin/debian-labwc-workspacectl activate "$workspace"

mkdir -p "$state_root"
printf '%s\n' "$workspace" >"$state_file"
pkill -RTMIN+10 -x waybar >/dev/null 2>&1 || true
