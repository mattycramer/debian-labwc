#!/usr/bin/env bash

readonly BACKPORTS_SUITE="trixie-backports"
readonly REQUESTED_PACKAGES=(
  labwc
  kanshi
  waybar
  wofi
  mako-notifier
  wlr-randr
  wlrctl
  xwayland
  polkitd
  pkexec
  pinentry-gtk2
  seatd
  swaybg
  swayidle
  swaylock
  lxpolkit
  thunar
  nnn
  pipewire
  pipewire-pulse
  wireplumber
  greetd
  tuigreet
  gammastep
  xdg-desktop-portal
  xdg-desktop-portal-wlr
  xdg-desktop-portal-gtk
  wl-clipboard
  wf-recorder
  grim
  slurp
  qt5wayland
  qt6-wayland
  gvfs
  gvfs-backends
  libgl1-mesa-dri
  mesa-vulkan-drivers
  mesa-utils
  libgles2
  nvidia-driver
  nvidia-kernel-dkms
  intel-media-va-driver
  nvidia-vaapi-driver
  nvidia-vulkan-icd
  vulkan-validationlayers
  libegl1
  libglvnd0
  libvulkan1
  foot
  foot-terminfo
  pavucontrol
  playerctl
  brightnessctl
  wev
  upower
  network-manager
  fonts-font-awesome
  fonts-noto
  fonts-noto-core
  zsh
  starship
  fonts-material-design-icons-iconfont
  fonts-weather-icons
)

retry_cmd() {
  local attempts="$1"
  shift
  local try=1
  while true; do
    if run_cmd "$@"; then
      return 0
    fi
    if (( try >= attempts )); then
      return 1
    fi
    sleep "$try"
    try=$((try + 1))
  done
}

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

apt_update() {
  log_info "updating apt metadata"
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_requested_packages() {
  log_info "installing requested packages from $BACKPORTS_SUITE"
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt -t "$BACKPORTS_SUITE" install --no-install-recommends "${apt_args[@]}" "${REQUESTED_PACKAGES[@]}"
}
