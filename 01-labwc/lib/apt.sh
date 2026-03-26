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
  qtwayland5
  qt6-wayland
  gvfs
  gvfs-backends
  libgl1-mesa-dri
  mesa-vulkan-drivers
  mesa-utils
  libgles2
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

readonly NVIDIA_PACKAGES=(
  nvidia-driver
  nvidia-kernel-dkms
  nvidia-vaapi-driver
  nvidia-vulkan-icd
)

readonly INTEL_PACKAGES=(
  intel-media-va-driver
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

resolved_requested_packages() {
  printf '%s\n' "${REQUESTED_PACKAGES[@]}"
  if [[ "${LABWC_HAS_NVIDIA_GPU:-no}" == "yes" ]]; then
    printf '%s\n' "${NVIDIA_PACKAGES[@]}"
  fi
  if [[ "${LABWC_HAS_INTEL_GPU:-no}" == "yes" ]]; then
    printf '%s\n' "${INTEL_PACKAGES[@]}"
  fi
}

install_requested_packages() {
  log_info "installing requested packages from $BACKPORTS_SUITE"
  local -a package_list=()
  local -a apt_args=()
  mapfile -t package_list < <(resolved_requested_packages)
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt -t "$BACKPORTS_SUITE" install --no-install-recommends "${apt_args[@]}" "${package_list[@]}"
}
