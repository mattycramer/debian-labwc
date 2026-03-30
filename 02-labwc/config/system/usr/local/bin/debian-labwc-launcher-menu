#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

choose() {
  local prompt="$1"
  shift
  printf '%s\n' "$@" | wofi --dmenu --prompt "$prompt"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

run_gui() {
  command -v "$1" >/dev/null 2>&1 || exit 0
  nohup "$@" >/dev/null 2>&1 &
}

run_terminal() {
  local title="$1"
  local command_string="$2"
  if command -v footclient >/dev/null 2>&1; then
    nohup footclient -T "$title" -e bash -lc "$command_string" >/dev/null 2>&1 &
  elif command -v foot >/dev/null 2>&1; then
    nohup foot -T "$title" -e bash -lc "$command_string" >/dev/null 2>&1 &
  fi
}

entries=(
  "Applications"
  "Terminal"
  "Kitty"
  "Files"
)

if has_command thorium-browser; then
  entries+=("Browser")
fi
if has_command qutebrowser; then
  entries+=("Qutebrowser")
fi
if has_command code; then
  entries+=("Code")
fi
if has_command mousepad; then
  entries+=("Mousepad")
fi
if has_command obsidian; then
  entries+=("Obsidian")
fi
if has_command geeqie; then
  entries+=("Geeqie")
fi
if has_command mullvad-vpn; then
  entries+=("Mullvad VPN")
fi
if has_command bitwarden; then
  entries+=("Bitwarden")
fi
if has_command nmtui; then
  entries+=("Network")
fi
entries+=("Power")

selection="$(choose "Launch" "${entries[@]}")"

case "$selection" in
  "Applications") exec wofi --show drun ;;
  "Terminal") run_terminal "Terminal" 'exec "${SHELL:-/bin/bash}"' ;;
  "Kitty") run_gui kitty ;;
  "Files") run_gui thunar ;;
  "Browser") run_gui thorium-browser ;;
  "Qutebrowser") run_gui qutebrowser ;;
  "Code") run_gui code ;;
  "Mousepad") run_gui mousepad ;;
  "Obsidian") run_gui obsidian ;;
  "Geeqie") run_gui geeqie ;;
  "Mullvad VPN") run_gui mullvad-vpn ;;
  "Bitwarden") run_gui bitwarden ;;
  "Network") run_terminal "Network" 'exec nmtui' ;;
  "Power") exec /usr/local/bin/debian-labwc-power-menu ;;
  *) exit 0 ;;
esac
