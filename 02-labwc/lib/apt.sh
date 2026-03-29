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
  polkit-kde-agent-1
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
  fonts-font-awesome
  fonts-noto
  fonts-noto-core
  fonts-noto-mono
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
  file-roller
  geeqie
  mousepad
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

install_sid_repository() {
  [[ -f "$DEBIAN_ARCHIVE_KEYRING_PATH" ]] || die "missing Debian archive keyring: $DEBIAN_ARCHIVE_KEYRING_PATH"
  run_cmd install -D -m 0644 /dev/null "$SID_SOURCE_PATH"
  printf '%s' 'Types: deb
URIs: https://deb.debian.org/debian
Suites: sid
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
' >"$SID_SOURCE_PATH"
  run_cmd install -D -m 0644 /dev/null "$SID_PREFERENCES_PATH"
  printf '%s' 'Package: *
Pin: release n=sid
Pin-Priority: 100
' >"$SID_PREFERENCES_PATH"
}

resolved_requested_packages() {
  printf '%s\n' "${SID_PACKAGES[@]}"
  printf '%s\n' "${GRAPHICS_PACKAGES[@]}"
  printf '%s\n' "${TWEAKS_BUILD_PACKAGES[@]}"
  printf '%s\n' "${TWEAKS_SID_PACKAGES[@]}"
  printf '%s\n' "${KEEPSECRET_BUILD_PACKAGES[@]}"
  if [[ "${LABWC_HAS_INTEL_GPU:-no}" == "yes" ]]; then
    printf '%s\n' "${INTEL_PACKAGES[@]}"
  fi
}

install_requested_packages() {
  log_info "installing sid package set"
  local -a sid_package_list=()
  local -a graphics_package_list=()
  local -a tweaks_build_package_list=()
  local -a tweaks_sid_package_list=()
  local -a keepsecret_build_package_list=()
  local -a apt_args=()
  mapfile -t sid_package_list < <(printf '%s\n' "${SID_PACKAGES[@]}")
  mapfile -t graphics_package_list < <(printf '%s\n' "${GRAPHICS_PACKAGES[@]}")
  mapfile -t tweaks_build_package_list < <(printf '%s\n' "${TWEAKS_BUILD_PACKAGES[@]}")
  mapfile -t tweaks_sid_package_list < <(printf '%s\n' "${TWEAKS_SID_PACKAGES[@]}")
  mapfile -t keepsecret_build_package_list < <(printf '%s\n' "${KEEPSECRET_BUILD_PACKAGES[@]}")
  if [[ "${LABWC_HAS_INTEL_GPU:-no}" == "yes" ]]; then
    mapfile -O "${#graphics_package_list[@]}" -t graphics_package_list < <(printf '%s\n' "${INTEL_PACKAGES[@]}")
  fi
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
