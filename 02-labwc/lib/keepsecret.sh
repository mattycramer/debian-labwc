#!/usr/bin/env bash

readonly KEEPSECRET_BIN_PATH="/usr/local/bin/keepsecret"
readonly KEEPSECRET_DESKTOP_PATH="/usr/local/share/applications/org.kde.keepsecret.desktop"
readonly KEEPSECRET_APPDATA_PATH="/usr/local/share/metainfo/org.kde.keepsecret.metainfo.xml"
readonly KEEPSECRET_ICON_PATH="/usr/local/share/icons/hicolor/scalable/apps/org.kde.keepsecret.svg"
readonly KEEPSECRET_TMP_ROOT_PREFIX="/tmp/labwc-keepsecret"
readonly KEEPSECRET_MANIFEST_DIR="/var/lib/labwc-session"
readonly KEEPSECRET_MANIFEST_PATH="${KEEPSECRET_MANIFEST_DIR}/keepsecret-install-manifest.txt"

keepsecret_work_root() {
  printf '%s-%s\n' "$KEEPSECRET_TMP_ROOT_PREFIX" "$LABWC_TARGET_USER"
}

keepsecret_source_dir() {
  printf '%s/source\n' "$(keepsecret_work_root)"
}

keepsecret_build_dir() {
  printf '%s/build\n' "$(keepsecret_work_root)"
}

prepare_keepsecret_work_root() {
  local work_root
  work_root="$(keepsecret_work_root)"
  [[ "$work_root" == /tmp/* ]] || die "keepsecret work root must stay under /tmp: $work_root"
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$work_root"
}

keepsecret_package_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -F "install ok installed" >/dev/null
}

require_keepsecret_build_prereqs() {
  local pkg
  local -a required_packages=(
    extra-cmake-modules
    qt6-base-dev
    qt6-base-dev-tools
    qt6-declarative-dev
    qt6-declarative-dev-tools
    qt6-l10n-tools
    qt6-svg-dev
    qt6-tools-dev
    qt6-tools-dev-tools
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

  for pkg in "${required_packages[@]}"; do
    keepsecret_package_installed "$pkg" || die "missing package '$pkg'; rerun ./install.sh --phase packages before enabling keepsecret"
  done
}

clone_keepsecret_source() {
  local source_dir build_dir
  source_dir="$(keepsecret_source_dir)"
  build_dir="$(keepsecret_build_dir)"

  [[ -n "${KEEPSECRET_GIT_URL:-}" ]] || die "KEEPSECRET_GIT_URL is required"
  [[ "${KEEPSECRET_GIT_URL}" == https://* ]] || die "KEEPSECRET_GIT_URL must be an https URL"

  prepare_keepsecret_work_root
  run_cmd runuser -u "$LABWC_TARGET_USER" -- sh -c "rm -rf -- '$source_dir' '$build_dir'"
  retry_cmd 3 runuser -u "$LABWC_TARGET_USER" -- env HOME="$LABWC_TARGET_HOME" \
    timeout 180 git clone --depth 1 "$KEEPSECRET_GIT_URL" "$source_dir"
}

install_keepsecret() {
  local source_dir build_dir
  source_dir="$(keepsecret_source_dir)"
  build_dir="$(keepsecret_build_dir)"

  require_keepsecret_build_prereqs
  clone_keepsecret_source

  run_cmd runuser -u "$LABWC_TARGET_USER" -- mkdir -p "$build_dir"
  run_cmd runuser -u "$LABWC_TARGET_USER" -- env HOME="$LABWC_TARGET_HOME" cmake \
    -S "$source_dir" \
    -B "$build_dir" \
    -G Ninja \
    -D CMAKE_BUILD_TYPE=Release \
    -D BUILD_TESTING=OFF \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -W no-dev
  run_cmd runuser -u "$LABWC_TARGET_USER" -- env HOME="$LABWC_TARGET_HOME" cmake --build "$build_dir" --verbose
  run_cmd cmake --install "$build_dir"
  [[ -f "$build_dir/install_manifest.txt" ]] || die "keepsecret install did not produce install_manifest.txt"
  run_cmd install -d -m 0755 "$KEEPSECRET_MANIFEST_DIR"
  run_cmd install -m 0644 "$build_dir/install_manifest.txt" "$KEEPSECRET_MANIFEST_PATH"
  if command -v update-desktop-database >/dev/null 2>&1; then
    run_cmd update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
  fi
}

remove_keepsecret_install() {
  if [[ -f "$KEEPSECRET_MANIFEST_PATH" ]]; then
    while IFS= read -r installed_path; do
      [[ -n "$installed_path" ]] || continue
      remove_if_present "$installed_path"
    done <"$KEEPSECRET_MANIFEST_PATH"
  else
    remove_if_present "$KEEPSECRET_BIN_PATH"
    remove_if_present "$KEEPSECRET_DESKTOP_PATH"
    remove_if_present "$KEEPSECRET_APPDATA_PATH"
    remove_if_present "$KEEPSECRET_ICON_PATH"
  fi
  remove_if_present "$KEEPSECRET_MANIFEST_PATH"
  remove_if_present "$(keepsecret_work_root)"
}
