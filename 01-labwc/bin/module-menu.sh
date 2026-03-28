#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

category="${1:-}"
action="${2:-menu}"
[[ -n "$category" ]] || exit 1

choose() {
  local prompt="$1"
  shift
  printf '%s\n' "$@" | wofi --dmenu --prompt "$prompt"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

power_profiles_available() {
  has_command powerprofilesctl || return 1
  powerprofilesctl list >/dev/null 2>&1
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

wifi_state() {
  nmcli -t -f WIFI general 2>/dev/null | tr '[:upper:]' '[:lower:]' || printf 'unknown'
}

networking_state() {
  nmcli -t -f STATE general 2>/dev/null | tr '[:upper:]' '[:lower:]' || printf 'unknown'
}

toggle_wifi() {
  case "$(wifi_state)" in
    enabled) nmcli radio wifi off ;;
    disabled) nmcli radio wifi on ;;
    *) exit 0 ;;
  esac
}

toggle_networking() {
  case "$(networking_state)" in
    connected*|connecting*|disconnected) nmcli networking off ;;
    asleep|unknown) nmcli networking on ;;
    *) nmcli networking on ;;
  esac
}

set_brightness() {
  local value="$1"
  brightnessctl set "$value"
}

show_profile_menu() {
  if ! power_profiles_available; then
    run_terminal "Battery" 'upower -d; printf "\nPower profile service unavailable.\n\nPress Enter to close..."; read -r _'
    return 0
  fi
  local choice
  choice="$(
    choose "Power" \
      "Power saver" \
      "Balanced" \
      "Performance" \
      "Battery details"
  )"
  case "$choice" in
    "Power saver") powerprofilesctl set power-saver ;;
    "Balanced") powerprofilesctl set balanced ;;
    "Performance") powerprofilesctl set performance ;;
    "Battery details") run_terminal "Battery" 'upower -d; printf "\nPress Enter to close..."; read -r _' ;;
    *) exit 0 ;;
  esac
}

case "$category:$action" in
  network:quick)
    run_terminal "Network" 'exec nmtui'
    ;;
  network:menu)
    entries=(
      "Open network manager"
      "Toggle Wi-Fi ($(wifi_state))"
      "Toggle networking ($(networking_state))"
      "Rescan Wi-Fi"
      "Connection details"
    )
    if has_command mullvad-vpn; then
      entries+=("Mullvad VPN")
    fi
    selection="$(choose "Network" "${entries[@]}")"
    case "$selection" in
      "Open network manager") run_terminal "Network" 'exec nmtui' ;;
      "Toggle Wi-Fi ("*) toggle_wifi ;;
      "Toggle networking ("*) toggle_networking ;;
      "Rescan Wi-Fi") nmcli device wifi rescan ;;
      "Connection details") run_terminal "Network" 'nmcli device status; printf "\n"; nmcli -f GENERAL,IP4,WIFI-PROPERTIES device show; printf "\nPress Enter to close..."; read -r _' ;;
      "Mullvad VPN") run_gui mullvad-vpn ;;
      *) exit 0 ;;
    esac
    ;;
  audio:menu)
    selection="$(
      choose "Audio" \
        "Open mixer" \
        "Toggle mute" \
        "Volume up 5%" \
        "Volume down 5%" \
        "Audio status"
    )"
    case "$selection" in
      "Open mixer") run_gui pavucontrol ;;
      "Toggle mute") wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
      "Volume up 5%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ ;;
      "Volume down 5%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
      "Audio status") run_terminal "Audio" 'wpctl status; printf "\nPress Enter to close..."; read -r _' ;;
      *) exit 0 ;;
    esac
    ;;
  battery:menu)
    show_profile_menu
    ;;
  battery:details)
    run_terminal "Battery" 'upower -d; printf "\nPress Enter to close..."; read -r _'
    ;;
  brightness:menu)
    selection="$(
      choose "Brightness" \
        "25%" \
        "50%" \
        "75%" \
        "100%"
    )"
    case "$selection" in
      "25%") set_brightness 25% ;;
      "50%") set_brightness 50% ;;
      "75%") set_brightness 75% ;;
      "100%") set_brightness 100% ;;
      *) exit 0 ;;
    esac
    ;;
  system:monitor)
    run_terminal "System Monitor" 'exec btop'
    ;;
  system:memory)
    run_terminal "Memory" 'free -h; printf "\n"; swapon --show; printf "\nPress Enter to close..."; read -r _'
    ;;
  system:menu)
    selection="$(
      choose "System" \
        "Open system monitor" \
        "Memory details" \
        "Storage menu" \
        "Power menu"
    )"
    case "$selection" in
      "Open system monitor") run_terminal "System Monitor" 'exec btop' ;;
      "Memory details") run_terminal "Memory" 'free -h; printf "\n"; swapon --show; printf "\nPress Enter to close..."; read -r _' ;;
      "Storage menu") exec "$0" storage menu ;;
      "Power menu") exec /usr/local/bin/debian-labwc-power-menu ;;
      *) exit 0 ;;
    esac
    ;;
  storage:ncdu)
    run_terminal "Storage" 'exec ncdu /'
    ;;
  storage:menu)
    selection="$(
      choose "Storage" \
        "Open disk usage" \
        "Browse files" \
        "Filesystem details"
    )"
    case "$selection" in
      "Open disk usage") run_terminal "Storage" 'exec ncdu /' ;;
      "Browse files") run_gui thunar ;;
      "Filesystem details") run_terminal "Storage" 'df -h / "$HOME"; printf "\n"; lsblk -o NAME,FSTYPE,SIZE,TYPE,MOUNTPOINT; printf "\nPress Enter to close..."; read -r _' ;;
      *) exit 0 ;;
    esac
    ;;
  player:menu)
    selection="$(
      choose "Media" \
        "Play or pause" \
        "Next track" \
        "Previous track" \
        "Stop"
    )"
    case "$selection" in
      "Play or pause") playerctl play-pause ;;
      "Next track") playerctl next ;;
      "Previous track") playerctl previous ;;
      "Stop") playerctl stop ;;
      *) exit 0 ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
