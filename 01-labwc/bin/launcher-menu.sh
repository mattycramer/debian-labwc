#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

choose() {
  local prompt="$1"
  shift
  printf '%s\n' "$@" | wofi --dmenu --prompt "$prompt"
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

selection="$(
  choose "Launch" \
    "󰆍  Applications" \
    "  Terminal" \
    "  Files" \
    "󰖟  Browser" \
    "󰇩  Qutebrowser" \
    "󰨞  Code Insiders" \
    "󰠮  Obsidian" \
    "󰌾  Mullvad VPN" \
    "󰟀  Bitwarden" \
    "󰒓  Network" \
    "  Power"
)"

case "$selection" in
  "󰆍  Applications") exec wofi --show drun ;;
  "  Terminal") run_terminal "Terminal" 'exec "${SHELL:-/bin/bash}"' ;;
  "  Files") run_gui thunar ;;
  "󰖟  Browser") run_gui thorium-browser ;;
  "󰇩  Qutebrowser") run_gui qutebrowser ;;
  "󰨞  Code Insiders") run_gui code-insiders ;;
  "󰠮  Obsidian") run_gui obsidian ;;
  "󰌾  Mullvad VPN") run_gui mullvad-vpn ;;
  "󰟀  Bitwarden") run_gui bitwarden ;;
  "󰒓  Network") run_terminal "Network" 'exec nmtui' ;;
  "  Power") exec /usr/local/bin/debian-labwc-power-menu ;;
  *) exit 0 ;;
esac
