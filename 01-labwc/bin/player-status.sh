#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if ! command -v playerctl >/dev/null 2>&1; then
  printf '%s\n' '󰎈  idle'
  exit 0
fi

status="$(playerctl status 2>/dev/null || true)"
if [[ -z "$status" ]]; then
  printf '%s\n' '󰎈  idle'
  exit 0
fi

artist="$(playerctl metadata artist 2>/dev/null || true)"
title="$(playerctl metadata title 2>/dev/null || true)"
player_name="$(playerctl metadata --format '{{ playerName }}' 2>/dev/null || true)"

case "$status" in
  Playing) icon='󰎈' ;;
  Paused) icon='󰏤' ;;
  *) icon='󰓛' ;;
esac

text="$title"
if [[ -n "$artist" && -n "$title" ]]; then
  text="$artist - $title"
elif [[ -z "$text" ]]; then
  text="${player_name:-idle}"
fi

text="${text//$'\n'/ }"
if ((${#text} > 42)); then
  text="${text:0:39}..."
fi

printf '%s  %s\n' "$icon" "$text"
