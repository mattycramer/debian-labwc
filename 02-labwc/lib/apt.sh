#!/usr/bin/env bash

readonly SID_SUITE="sid"
readonly SID_SOURCE_PATH="/etc/apt/sources.list.d/sid.sources"
readonly SID_PREFERENCES_PATH="/etc/apt/preferences.d/sid"
readonly DEBIAN_ARCHIVE_KEYRING_PATH="/usr/share/keyrings/debian-archive-keyring.gpg"
readonly LLVM_APT_BASE_URL="https://apt.llvm.org"
readonly LLVM_APT_KEY_PATH="/etc/apt/keyrings/apt.llvm.org.asc"
readonly LLVM_APT_SOURCES_PATH="/etc/apt/sources.list.d/llvm-toolchain.sources"
readonly SID_RUNTIME_PACKAGES=(
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
  ca-certificates
  curl
  librsvg2-common
  pipewire
  pipewire-audio
  pipewire-pulse
  libspa-0.2-bluetooth
  libspa-0.2-libcamera
  wireplumber
  rtkit
  dbus
  dbus-daemon
  dbus-user-session
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
  qml6-module-qtqml
  qml6-module-qtquick
  qml6-module-qtquick-controls
  qml6-module-qtquick-layouts
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
  bluez
  fonts-font-awesome
  fonts-noto
  fonts-noto-core
  fonts-noto-mono
  fontconfig
  fonts-noto-color-emoji
  fonts-symbola
  desktop-file-utils
  nwg-look
  papirus-icon-theme
  qt6ct
  adwaita-qt6
  zsh
  zsh-autosuggestions
  zsh-syntax-highlighting
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
  git
  tar
  )

readonly SID_SOURCE_BUILD_PACKAGES=(
  build-essential
  appstream
  pkg-config
  pkgconf
  rustup
  cmake
  ninja-build
  meson
  gettext
  bindgen
  python3-docutils
  libgtk-4-dev
  libglib2.0-dev
  libpango1.0-dev
  libgdk-pixbuf-2.0-dev
  libgraphene-1.0-dev
  libcairo2-dev
  libxml2-dev
  libsecret-1-dev
  libkf6config-dev
  libkf6coreaddons-dev
  libkf6crash-dev
  libkf6dbusaddons-dev
  libkf6iconthemes-dev
  libkf6i18n-dev
  libkf6itemmodels-dev
  kirigami-addons-dev
  libkf6qqc2desktopstyle-dev
  qt6-base-dev
  qt6-base-private-dev
  qt6-base-dev-tools
  qt6-declarative-dev
  qt6-declarative-dev-tools
  qt6-shadertools-dev
  qt6-svg-dev
  qt6-tools-dev
  qt6-tools-dev-tools
  qt6-l10n-tools
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

llvm_upstream_candidate_majors() {
  if [[ -n "${LABWC_LLVM_UPSTREAM_MAJOR:-}" ]]; then
    printf '%s\n' "$LABWC_LLVM_UPSTREAM_MAJOR"
    return 0
  fi
  printf '%s\n' 23 22 21 20
}

llvm_upstream_major() {
  local codename major code url

  if [[ -n "${LABWC_LLVM_RESOLVED_MAJOR:-}" ]]; then
    printf '%s\n' "$LABWC_LLVM_RESOLVED_MAJOR"
    return 0
  fi

  codename="$(
    . /etc/os-release
    printf '%s' "${VERSION_CODENAME:-}"
  )"
  [[ -n "$codename" ]] || die "could not determine Debian codename for LLVM upstream repo"

  while IFS= read -r major; do
    [[ "$major" =~ ^[0-9]+$ ]] || die "LABWC_LLVM_UPSTREAM_MAJOR must be numeric, found '$major'"
    url="${LLVM_APT_BASE_URL}/${codename}/dists/llvm-toolchain-${codename}-${major}/Release"
    code="$(curl --location --silent --output /dev/null --write-out '%{http_code}' --max-time 20 "$url" || true)"
    if [[ "$code" == "200" ]]; then
      LABWC_LLVM_RESOLVED_MAJOR="$major"
      printf '%s\n' "$LABWC_LLVM_RESOLVED_MAJOR"
      return 0
    fi
  done < <(llvm_upstream_candidate_majors)

  die "could not determine a published LLVM upstream major for ${codename}"
}

llvm_clang_bin() {
  printf '%s\n' "clang-$(llvm_upstream_major)"
}

llvm_clangxx_bin() {
  printf '%s\n' "clang++-$(llvm_upstream_major)"
}

llvm_upstream_packages() {
  local major
  major="$(llvm_upstream_major)"
  printf '%s\n' \
    "clang-${major}" \
    "lld-${major}" \
    "libomp-${major}-dev"
}

ensure_llvm_upstream_repository() {
  local codename major content

  codename="$(
    . /etc/os-release
    printf '%s' "${VERSION_CODENAME:-}"
  )"
  major="$(llvm_upstream_major)"

  run_cmd install -d -m 0755 /etc/apt/keyrings
  run_cmd curl --fail --location --max-time 20 --silent --show-error \
    -o "$LLVM_APT_KEY_PATH" \
    "${LLVM_APT_BASE_URL}/llvm-snapshot.gpg.key"

  content="$(cat <<EOF
Types: deb
Architectures: amd64
Signed-By: ${LLVM_APT_KEY_PATH}
URIs: ${LLVM_APT_BASE_URL}/${codename}/
Suites: llvm-toolchain-${codename}-${major}
Components: main
EOF
)"
  printf '%s\n' "$content" >"$LLVM_APT_SOURCES_PATH"
}

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

apt_update() {
  log_info "updating apt metadata"
  if [[ "${LABWC_INSTALL_METHOD:-source}" == "source" ]]; then
    ensure_llvm_upstream_repository
  fi
  retry_cmd 3 env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

require_sid_repository() {
  [[ -f "$DEBIAN_ARCHIVE_KEYRING_PATH" ]] || die "missing Debian archive keyring: $DEBIAN_ARCHIVE_KEYRING_PATH"
  [[ -f "$SID_SOURCE_PATH" ]] || die "missing Debian sid source file: $SID_SOURCE_PATH; run 'make sid' in 00-system first"
  [[ -f "$SID_PREFERENCES_PATH" ]] || die "missing Debian sid preferences file: $SID_PREFERENCES_PATH; run 'make sid' in 00-system first"
}

resolved_sid_packages() {
  printf '%s\n' "${SID_RUNTIME_PACKAGES[@]}"
}

resolved_graphics_packages() {
  printf '%s\n' "${GRAPHICS_PACKAGES[@]}"
  if [[ "${LABWC_HAS_INTEL_GPU:-no}" == "yes" ]]; then
    printf '%s\n' "${INTEL_PACKAGES[@]}"
  fi
}

resolved_requested_packages() {
  resolved_sid_packages
  if [[ "${LABWC_INSTALL_METHOD:-source}" == "source" ]]; then
    printf '%s\n' "${SID_SOURCE_BUILD_PACKAGES[@]}"
  fi
  resolved_graphics_packages
}

install_requested_packages() {
  log_info "installing sid package set"
  local -a sid_package_list=()
  local -a build_package_list=()
  local -a graphics_package_list=()
  local -a all_package_list=()
  local -a apt_args=()
  mapfile -t all_package_list < <(resolved_requested_packages)
  ((${#all_package_list[@]} > 0)) || die "resolved package set is empty"
  mapfile -t sid_package_list < <(resolved_sid_packages)
  if [[ "${LABWC_INSTALL_METHOD:-source}" == "source" ]]; then
    mapfile -t build_package_list < <(printf '%s\n' "${SID_SOURCE_BUILD_PACKAGES[@]}")
  fi
  mapfile -t graphics_package_list < <(resolved_graphics_packages)
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${sid_package_list[@]}"
  if ((${#build_package_list[@]} > 0)); then
    log_info "installing source-build package set from sid"
    run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${build_package_list[@]}"
    mapfile -t build_package_list < <(llvm_upstream_packages)
    log_info "installing upstream LLVM toolchain packages"
    run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt install --no-install-recommends "${apt_args[@]}" "${build_package_list[@]}"
  fi
  log_info "installing graphics package set from sid"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -t "$SID_SUITE" install --no-install-recommends "${apt_args[@]}" "${graphics_package_list[@]}"
}

remove_source_build_packages() {
  local -a apt_args=()
  local -a cleanup_package_list=()
  local package_name

  [[ "${LABWC_INSTALL_METHOD:-source}" == "source" ]] || return 0
  mapfile -t apt_args < <(apt_yes_args)
  cleanup_package_list=("${SID_SOURCE_BUILD_PACKAGES[@]}")
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    cleanup_package_list+=("$package_name")
  done < <(llvm_upstream_packages)

  log_info "removing source-build tooling packages after successful install"
  run_cmd env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt purge --autoremove "${apt_args[@]}" "${cleanup_package_list[@]}"
}
