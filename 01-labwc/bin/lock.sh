#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

config_path="${XDG_CONFIG_HOME:-$HOME/.config}/swaylock/config"
wallpaper_name="@LOCK_WALLPAPER_NAME@"
runtime_wallpaper="${XDG_DATA_HOME:-$HOME/.local/share}/debian-labwc/${wallpaper_name}"
fallback_wallpaper="@TARGET_HOME@/.local/share/debian-labwc/${wallpaper_name}"
wallpaper_path="$runtime_wallpaper"
scaling_mode="${LABWC_WALLPAPER_MODE:-fill}"

if [[ ! -r "$wallpaper_path" && -r "$fallback_wallpaper" ]]; then
  wallpaper_path="$fallback_wallpaper"
fi

if [[ ! -r "$wallpaper_path" ]]; then
  printf 'missing wallpaper for swaylock: %s\n' "$runtime_wallpaper" >&2
  exit 1
fi

exec swaylock \
  --daemonize \
  --config "$config_path" \
  --image "$wallpaper_path" \
  --scaling "$scaling_mode" \
  --color 111111ff \
  --font "Noto Sans" \
  --clock \
  --indicator \
  --indicator-caps-lock \
  --show-failed-attempts \
  --inside-color 202020cc \
  --inside-clear-color 334155cc \
  --inside-ver-color 1f2937cc \
  --inside-wrong-color 7f1d1dcc \
  --ring-color 4a89dcff \
  --ring-clear-color 88c0d0ff \
  --ring-ver-color 6dc4edff \
  --ring-wrong-color ef4444ff \
  --line-color 11111100 \
  --line-clear-color 11111100 \
  --line-ver-color 11111100 \
  --line-wrong-color 11111100 \
  --separator-color 00000000 \
  --key-hl-color 88c0d0ff \
  --bs-hl-color f6bd60ff \
  --text-color e5e7ebff \
  --text-clear-color e5e7ebff \
  --text-ver-color e5e7ebff \
  --text-wrong-color fff1f2ff \
  "$@"
