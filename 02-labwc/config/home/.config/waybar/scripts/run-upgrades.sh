#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if command -v foot >/dev/null 2>&1; then
  foot -T "System Upgrade" -e bash -lc "sudo apt upgrade; rc=\$?; printf \"\\nPress Enter to close...\"; read -r _; exit \$rc"
elif command -v kitty >/dev/null 2>&1; then
  kitty --title "System Upgrade" bash -lc "sudo apt upgrade; rc=\$?; printf \"\\nPress Enter to close...\"; read -r _; exit \$rc"
else
  exit 1
fi
pkill -RTMIN+12 -x waybar >/dev/null 2>&1 || true
