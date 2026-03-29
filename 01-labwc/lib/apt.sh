#!/usr/bin/env bash

readonly BACKPORTS_SUITE="trixie-backports"
readonly BACKPORTS_PACKAGES=(
  labwc
  kanshi
  waybar
  gsimplecal
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
  # Debian trixie currently lacks xfce-polkit, so keep the auth agent on lxpolkit.
  lxpolkit
  thunar
  thunar-volman
  nnn
  nano
  librsvg2-common
  pipewire
  pipewire-audio
  pipewire-pulse
  libspa-0.2-libcamera
  wireplumber
  rtkit
  dbus-user-session
  at-spi2-core
  greetd
  tuigreet
  gammastep
  xdg-user-dirs
  xdg-utils
  xdg-desktop-portal
  xdg-desktop-portal-wlr
  xdg-desktop-portal-gtk
  wl-clipboard
  wf-recorder
  grim
  slurp
  gpg
  gpg-agent
  kwallet6
  qtwayland5
  qt6-wayland
  gvfs
  gvfs-fuse
  gvfs-backends
  udisks2
  foot
  foot-terminfo
  pavucontrol
  playerctl
  brightnessctl
  wev
  upower
  power-profiles-daemon
  network-manager
  fonts-font-awesome
  fonts-noto
  fonts-noto-core
  nwg-look
  papirus-icon-theme
  zsh
  zsh-autosuggestions
  starship
  fonts-material-design-icons-iconfont
  fonts-weather-icons
  adwaita-icon-theme
  file-roller
  ripgrep
  fd-find
  tmux
  btop
  ncdu
  fzf
)

readonly GRAPHICS_PACKAGES=(
  bash-completion
  libgl1-mesa-dri
  mesa-vulkan-drivers
  mesa-utils
  libgles2
  vulkan-validationlayers
  libegl1
  libglvnd0
  libvulkan1
)

readonly TWEAKS_BUILD_PACKAGES=(
  build-essential
  cmake
  git
  libglib2.0-dev
  libxkbcommon-dev
  libxml2-dev
  ninja-build
  pkg-config
)

readonly TWEAKS_BACKPORTS_PACKAGES=(
  qt6-base-dev
  qt6-l10n-tools
  qt6-tools-dev
  qt6-tools-dev-tools
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
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

resolved_requested_packages() {
  printf '%s\n' "${BACKPORTS_PACKAGES[@]}"
  printf '%s\n' "${GRAPHICS_PACKAGES[@]}"
  printf '%s\n' "${TWEAKS_BUILD_PACKAGES[@]}"
  printf '%s\n' "${TWEAKS_BACKPORTS_PACKAGES[@]}"
  if [[ "${LABWC_HAS_INTEL_GPU:-no}" == "yes" ]]; then
    printf '%s\n' "${INTEL_PACKAGES[@]}"
  fi
}

install_requested_packages() {
  log_info "installing backports package set"
  local -a backports_package_list=()
  local -a graphics_package_list=()
  local -a tweaks_build_package_list=()
  local -a tweaks_backports_package_list=()
  local -a apt_args=()
  mapfile -t backports_package_list < <(printf '%s\n' "${BACKPORTS_PACKAGES[@]}")
  mapfile -t graphics_package_list < <(printf '%s\n' "${GRAPHICS_PACKAGES[@]}")
  mapfile -t tweaks_build_package_list < <(printf '%s\n' "${TWEAKS_BUILD_PACKAGES[@]}")
  mapfile -t tweaks_backports_package_list < <(printf '%s\n' "${TWEAKS_BACKPORTS_PACKAGES[@]}")
  if [[ "${LABWC_HAS_INTEL_GPU:-no}" == "yes" ]]; then
    mapfile -O "${#graphics_package_list[@]}" -t graphics_package_list < <(printf '%s\n' "${INTEL_PACKAGES[@]}")
  fi
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$BACKPORTS_SUITE" install --no-install-recommends "${apt_args[@]}" "${backports_package_list[@]}"
  log_info "installing graphics package set from backports"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$BACKPORTS_SUITE" install --no-install-recommends "${apt_args[@]}" "${graphics_package_list[@]}"
  log_info "installing generic build dependencies for labwc-tweaks source build from backports"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$BACKPORTS_SUITE" install --no-install-recommends "${apt_args[@]}" "${tweaks_build_package_list[@]}"
  log_info "installing Qt build dependencies for labwc-tweaks source build from backports"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$BACKPORTS_SUITE" install --no-install-recommends "${apt_args[@]}" "${tweaks_backports_package_list[@]}"
}
