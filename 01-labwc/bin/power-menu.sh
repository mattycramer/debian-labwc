#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

selection="$(
  printf '%s\n' \
    "lock" \
    "logout" \
    "suspend" \
    "reboot" \
    "poweroff" | wofi --dmenu --prompt "Power"
)"

case "$selection" in
  lock) exec swaylock -f ;;
  logout) pkill -x labwc || true ;;
  suspend) exec systemctl suspend ;;
  reboot) exec systemctl reboot ;;
  poweroff) exec systemctl poweroff ;;
  *) exit 0 ;;
esac
