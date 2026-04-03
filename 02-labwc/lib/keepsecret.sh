#!/usr/bin/env bash

readonly KEEPSECRET_BIN_PATH="/usr/local/bin/keepsecret"
readonly KEEPSECRET_DESKTOP_PATH="/usr/local/share/applications/org.kde.keepsecret.desktop"
readonly KEEPSECRET_APPDATA_PATH="/usr/local/share/metainfo/org.kde.keepsecret.metainfo.xml"
readonly KEEPSECRET_ICON_PATH="/usr/local/share/icons/hicolor/scalable/apps/org.kde.keepsecret.svg"
readonly KEEPSECRET_LOGGING_CATEGORIES_PATH="/usr/local/share/qlogging-categories6/keepsecret.categories"
readonly KEEPSECRET_MANIFEST_DIR="/var/lib/labwc-session"
readonly KEEPSECRET_MANIFEST_PATH="${KEEPSECRET_MANIFEST_DIR}/keepsecret-install-manifest.txt"
readonly KEEPSECRET_PROVENANCE_PATH="${KEEPSECRET_MANIFEST_DIR}/keepsecret-build.env"

validate_keepsecret_settings() {
  require_https_url "KEEPSECRET_GIT_URL" "${KEEPSECRET_GIT_URL:-}"
  require_commit_sha "${KEEPSECRET_COMMIT_SHA:-}"
}

verify_keepsecret_stage() {
  local stage_root="$1"
  local root="${stage_root%/}/usr/local"

  require_file "$root/bin/keepsecret"
  require_file "$root/share/applications/org.kde.keepsecret.desktop"
  require_file "$root/share/metainfo/org.kde.keepsecret.metainfo.xml"
  require_file "$root/share/icons/hicolor/scalable/apps/org.kde.keepsecret.svg"
  require_file "$root/share/qlogging-categories6/keepsecret.categories"
}

install_keepsecret() {
  local work_root repo_dir build_dir stage_root provenance log_path

  validate_keepsecret_settings
  log_path="$(build_log_path "keepsecret-build")"
  work_root="$(fetch_source_checkout "keepsecret" "$KEEPSECRET_GIT_URL" "$KEEPSECRET_COMMIT_SHA" "$log_path")"
  repo_dir="$work_root/source"
  build_dir="$work_root/build"
  stage_root="$work_root/stage"

  trap 'cleanup_source_checkout "$work_root"' RETURN

  log_info "building keepsecret from ${KEEPSECRET_COMMIT_SHA}"
  run_logged_command "$log_path" cmake -S "$repo_dir" -B "$build_dir" -G Ninja \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_INSTALL_PREFIX=/usr/local
  run_logged_command "$log_path" cmake --build "$build_dir" --verbose
  run_logged_command "$log_path" env DESTDIR="$stage_root" cmake --install "$build_dir" --prefix /usr/local
  verify_keepsecret_stage "$stage_root"

  remove_keepsecret_install
  install_staged_tree "$stage_root" "$KEEPSECRET_MANIFEST_PATH"
  assert_binary_dependencies "$KEEPSECRET_BIN_PATH" "keepsecret"
  require_file "$KEEPSECRET_DESKTOP_PATH"
  require_file "$KEEPSECRET_APPDATA_PATH"
  require_file "$KEEPSECRET_ICON_PATH"
  require_file "$KEEPSECRET_LOGGING_CATEGORIES_PATH"
  if command -v update-desktop-database >/dev/null 2>&1; then
    run_cmd update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
  fi

  provenance="$(cat <<EOF
KEEPSECRET_GIT_URL="$KEEPSECRET_GIT_URL"
KEEPSECRET_COMMIT_SHA="$KEEPSECRET_COMMIT_SHA"
KEEPSECRET_PATCH_SERIES="patches/release/series"
KEEPSECRET_BUILD_LOG="$log_path"
KEEPSECRET_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  write_source_provenance "$KEEPSECRET_PROVENANCE_PATH" "$provenance"

  trap - RETURN
  cleanup_source_checkout "$work_root"
}

remove_keepsecret_install() {
  remove_manifest_install "$KEEPSECRET_MANIFEST_PATH"
  remove_if_present "$KEEPSECRET_BIN_PATH"
  remove_if_present "$KEEPSECRET_DESKTOP_PATH"
  remove_if_present "$KEEPSECRET_APPDATA_PATH"
  remove_if_present "$KEEPSECRET_ICON_PATH"
  remove_if_present "$KEEPSECRET_LOGGING_CATEGORIES_PATH"
  remove_if_present "$KEEPSECRET_PROVENANCE_PATH"
}
