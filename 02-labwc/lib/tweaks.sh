#!/usr/bin/env bash

readonly LABWC_TWEAKS_BIN_PATH="/usr/bin/labwc-tweaks"
readonly LABWC_TWEAKS_DESKTOP_PATH="/usr/share/applications/labwc_tweaks.desktop"
readonly LABWC_TWEAKS_APPDATA_PATH="/usr/share/metainfo/labwc_tweaks.appdata.xml"
readonly LABWC_TWEAKS_ICON_PATH="/usr/share/icons/hicolor/scalable/apps/labwc_tweaks.svg"
readonly QT6_LINGUISTTOOLS_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/cmake/Qt6LinguistTools/Qt6LinguistToolsConfig.cmake"
readonly XKB_INCLUDE_PATH="/usr/include/xkbcommon/xkbcommon.h"
readonly XKB_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu/libxkbcommon.so"

labwc_tweaks_cache_root() {
  printf '%s/.cache/labwc-session/labwc-tweaks\n' "$LABWC_TARGET_HOME"
}

labwc_tweaks_archive_path() {
  printf '%s/source.tar.gz\n' "$(labwc_tweaks_cache_root)"
}

labwc_tweaks_source_dir() {
  printf '%s/source\n' "$(labwc_tweaks_cache_root)"
}

labwc_tweaks_build_dir() {
  printf '%s/build\n' "$(labwc_tweaks_cache_root)"
}

prepare_labwc_tweaks_cache() {
  local cache_root
  cache_root="$(labwc_tweaks_cache_root)"
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" \
    "$LABWC_TARGET_HOME/.cache" \
    "$LABWC_TARGET_HOME/.cache/labwc-session" \
    "$cache_root"
}

validate_labwc_tweaks_settings() {
  [[ -n "${LABWC_TWEAKS_VERSION:-}" ]] || die "LABWC_TWEAKS_VERSION is required"
  [[ "${LABWC_TWEAKS_TAG:-}" =~ ^[A-Za-z0-9._-]+$ ]] || {
    die "LABWC_TWEAKS_TAG must contain only alnum, dot, underscore, or dash, found '${LABWC_TWEAKS_TAG:-}'"
  }
  [[ "${LABWC_TWEAKS_TARBALL_URL:-}" =~ ^https://github\.com/[^/]+/[^/]+/archive/refs/tags/${LABWC_TWEAKS_TAG}\.tar\.gz$ ]] || {
    die "LABWC_TWEAKS_TARBALL_URL must be a GitHub tag tarball for '${LABWC_TWEAKS_TAG}', found '${LABWC_TWEAKS_TARBALL_URL:-}'"
  }
  [[ "${LABWC_TWEAKS_TARBALL_SHA:-}" =~ ^[0-9a-f]{64}$ ]] || {
    die "LABWC_TWEAKS_TARBALL_SHA must be a 64 character lowercase hex sha256, found '${LABWC_TWEAKS_TARBALL_SHA:-}'"
  }
}

download_labwc_tweaks_source() {
  local archive_path actual_sha
  archive_path="$(labwc_tweaks_archive_path)"
  prepare_labwc_tweaks_cache
  run_target_user_command -- sh -c "rm -f -- '$archive_path'"
  retry_cmd 6 run_target_user_command -- \
    curl --ipv4 --fail --location --retry 6 --retry-all-errors --retry-delay 2 --connect-timeout 20 --max-time 300 --silent --show-error -o "$archive_path" "$LABWC_TWEAKS_TARBALL_URL"
  actual_sha="$(sha256sum "$archive_path" | awk '{print $1}')"
  [[ "$actual_sha" == "$LABWC_TWEAKS_TARBALL_SHA" ]] || {
    die "labwc-tweaks tarball sha256 mismatch: expected ${LABWC_TWEAKS_TARBALL_SHA}, got ${actual_sha}"
  }
}

labwc_tweaks_package_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}

require_labwc_tweaks_build_prereqs() {
  local pkg
  local -a required_packages=(
    cmake
    ninja-build
    libxkbcommon-dev
    qt6-base-dev
    qt6-tools-dev
    qt6-tools-dev-tools
  )

  for pkg in "${required_packages[@]}"; do
    labwc_tweaks_package_installed "$pkg" || die "missing package '$pkg'; rerun ./install.sh --phase packages before enabling labwc-tweaks"
  done

  require_file "$QT6_LINGUISTTOOLS_CONFIG_PATH"
  require_file "$XKB_INCLUDE_PATH"
  require_file "$XKB_LIBRARY_PATH"
}

install_labwc_tweaks() {
  local archive_path source_dir build_dir
  archive_path="$(labwc_tweaks_archive_path)"
  source_dir="$(labwc_tweaks_source_dir)"
  build_dir="$(labwc_tweaks_build_dir)"

  validate_labwc_tweaks_settings
  require_command sha256sum
  require_labwc_tweaks_build_prereqs
  download_labwc_tweaks_source

  run_target_user_command -- sh -c "rm -rf -- '$source_dir' '$build_dir' && mkdir -p '$source_dir' '$build_dir'"
  run_target_user_command -- tar -xzf "$archive_path" -C "$source_dir" --strip-components=1
  run_target_user_command -- cmake -S "$source_dir" -B "$build_dir" -G Ninja -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=/usr -W no-dev
  run_target_user_command -- cmake --build "$build_dir" --verbose
  run_target_user_command -- ctest --verbose --force-new-ctest-process --test-dir "$build_dir"
  run_cmd cmake --install "$build_dir"
}

remove_labwc_tweaks_install() {
  remove_if_present "$LABWC_TWEAKS_BIN_PATH"
  remove_if_present "$LABWC_TWEAKS_DESKTOP_PATH"
  remove_if_present "$LABWC_TWEAKS_APPDATA_PATH"
  remove_if_present "$LABWC_TWEAKS_ICON_PATH"
  remove_if_present "$(labwc_tweaks_cache_root)"
}
