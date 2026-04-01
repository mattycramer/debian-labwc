#!/usr/bin/env bash

readonly SID_SUITE="sid"
readonly SID_SOURCE_PATH="/etc/apt/sources.list.d/sid.sources"
readonly SID_PREFERENCES_PATH="/etc/apt/preferences.d/sid"
readonly DEBIAN_ARCHIVE_KEYRING_PATH="/usr/share/keyrings/debian-archive-keyring.gpg"
readonly SID_REPO_URI="https://deb.debian.org/debian"
readonly SID_PACKAGES=(
  labwc
  kanshi
  waybar
  wdisplays
  gsimplecal
  wofi
  switcheroo-control
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
  polkit-kde-agent-1
  thunar
  thunar-volman
  thunar-archive-plugin
  tumbler
  ffmpegthumbnailer
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
  libgtk-4-1
  greetd
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
  libsecret-tools
  kwallet6
  qtwayland5
  qt6-wayland
  qml6-module-org-kde-config
  qml6-module-org-kde-coreaddons
  qml6-module-org-kde-kirigami
  qml6-module-org-kde-kirigamiaddons-formcard
  qml6-module-qtquick-window
  gvfs
  gvfs-fuse
  gvfs-backends
  udisks2
  foot
  foot-terminfo
  kitty
  kitty-terminfo
  pavucontrol
  playerctl
  brightnessctl
  wev
  upower
  power-profiles-daemon
  network-manager
  network-manager-tui
  fonts-font-awesome
  fonts-noto
  fonts-noto-core
  fonts-noto-mono
  fontconfig
  fonts-noto-color-emoji
  fonts-symbola
  nwg-look
  papirus-icon-theme
  qt6ct
  adwaita-qt6
  zsh
  zsh-autosuggestions
  starship
  fonts-material-design-icons-iconfont
  fonts-weather-icons
  adwaita-icon-theme
  xarchiver
  libarchive-tools
  7zip
  zip
  unzip
  unar
  unrar-free
  lz4
  lzip
  lrzip
  xz-utils
  zstd
  geeqie
  mousepad
  zathura
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

readonly TWEAKS_SID_PACKAGES=(
  qt6-base-dev
  qt6-base-dev-tools
  qt6-declarative-dev
  qt6-declarative-dev-tools
  qt6-l10n-tools
  qt6-svg-dev
  qt6-tools-dev
  qt6-tools-dev-tools
)

readonly KEEPSECRET_BUILD_PACKAGES=(
  extra-cmake-modules
  libkf6config-dev
  libkf6coreaddons-dev
  libkf6crash-dev
  libkf6dbusaddons-dev
  libkf6i18n-dev
  libkf6itemmodels-dev
  libkirigami-dev
  kirigami-addons-dev
  libsecret-1-dev
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

require_sid_repository() {
  [[ -f "$DEBIAN_ARCHIVE_KEYRING_PATH" ]] || die "missing Debian archive keyring: $DEBIAN_ARCHIVE_KEYRING_PATH"
  [[ -f "$SID_SOURCE_PATH" ]] || die "missing Debian sid source file: $SID_SOURCE_PATH; run 'make sid' in 00-system first"
  [[ -f "$SID_PREFERENCES_PATH" ]] || die "missing Debian sid preferences file: $SID_PREFERENCES_PATH; run 'make sid' in 00-system first"
}

resolved_sid_packages() {
  printf '%s\n' "${SID_PACKAGES[@]}"
}

resolved_graphics_packages() {
  printf '%s\n' "${GRAPHICS_PACKAGES[@]}"
  if [[ "${LABWC_HAS_INTEL_GPU:-no}" == "yes" ]]; then
    printf '%s\n' "${INTEL_PACKAGES[@]}"
  fi
}

resolved_tweaks_build_packages() {
  printf '%s\n' "${TWEAKS_BUILD_PACKAGES[@]}"
}

resolved_tweaks_sid_packages() {
  printf '%s\n' "${TWEAKS_SID_PACKAGES[@]}"
}

resolved_keepsecret_build_packages() {
  printf '%s\n' "${KEEPSECRET_BUILD_PACKAGES[@]}"
}

resolved_requested_packages() {
  resolved_sid_packages
  resolved_graphics_packages
  resolved_tweaks_build_packages
  resolved_tweaks_sid_packages
  resolved_keepsecret_build_packages
}

install_requested_packages() {
  log_info "installing sid package set"
  local -a sid_package_list=()
  local -a graphics_package_list=()
  local -a tweaks_build_package_list=()
  local -a tweaks_sid_package_list=()
  local -a keepsecret_build_package_list=()
  local -a all_package_list=()
  local -a apt_args=()
  mapfile -t all_package_list < <(resolved_requested_packages)
  ((${#all_package_list[@]} > 0)) || die "resolved package set is empty"
  mapfile -t sid_package_list < <(resolved_sid_packages)
  mapfile -t graphics_package_list < <(resolved_graphics_packages)
  mapfile -t tweaks_build_package_list < <(resolved_tweaks_build_packages)
  mapfile -t tweaks_sid_package_list < <(resolved_tweaks_sid_packages)
  mapfile -t keepsecret_build_package_list < <(resolved_keepsecret_build_packages)
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${sid_package_list[@]}"
  log_info "installing graphics package set from sid"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${graphics_package_list[@]}"
  log_info "installing generic build dependencies for labwc-tweaks source build from sid"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${tweaks_build_package_list[@]}"
  log_info "installing Qt build dependencies for labwc-tweaks source build from sid"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${tweaks_sid_package_list[@]}"
  log_info "installing keepsecret source build dependencies"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${keepsecret_build_package_list[@]}"
}
