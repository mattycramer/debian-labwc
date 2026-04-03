#!/usr/bin/env bash

readonly LABWC_TWEAKS_BIN_PATH="/usr/bin/labwc-tweaks"
readonly LABWC_TWEAKS_DESKTOP_PATH="/usr/share/applications/labwc_tweaks.desktop"
readonly LABWC_TWEAKS_APPDATA_PATH="/usr/share/metainfo/labwc_tweaks.appdata.xml"
readonly LABWC_TWEAKS_ICON_PATH="/usr/share/icons/hicolor/scalable/apps/labwc_tweaks.svg"
readonly LABWC_TWEAKS_DATA_DIR="/usr/share/labwc-tweaks"
readonly LABWC_TWEAKS_POLICY_PATH="/usr/share/polkit-1/actions/org.labwc.labwc-tweaks.policy"
readonly LABWC_TWEAKS_LOGIN_HELPER_PATH="/usr/libexec/labwc-tweaks-apply-login-screen"
readonly LABWC_TWEAKS_MANIFEST_DIR="/var/lib/labwc-session"
readonly LABWC_TWEAKS_MANIFEST_PATH="${LABWC_TWEAKS_MANIFEST_DIR}/labwc-tweaks-install-manifest.txt"
readonly LABWC_TWEAKS_PROVENANCE_PATH="${LABWC_TWEAKS_MANIFEST_DIR}/labwc-tweaks-build.env"

labwc_tweaks_cache_root() {
  printf '%s/.cache/labwc-session/labwc-tweaks\n' "$LABWC_TARGET_HOME"
}

validate_labwc_tweaks_settings() {
  case "${LABWC_INSTALL_METHOD:-}" in
    source)
      require_https_url "LABWC_TWEAKS_GIT_URL" "${LABWC_TWEAKS_GIT_URL:-}"
      require_commit_sha "${LABWC_TWEAKS_COMMIT_SHA:-}"
      ;;
    artifact)
      require_https_url "LABWC_TWEAKS_TARBALL_URL" "${LABWC_TWEAKS_TARBALL_URL:-}"
      require_sha256_hex "$(normalize_sha256_value "${LABWC_TWEAKS_TARBALL_SHA:-}")"
      require_safe_token "LABWC_TWEAKS_COMMIT_TAG" "${LABWC_TWEAKS_COMMIT_TAG:-}"
      require_commit_sha "${LABWC_TWEAKS_COMMIT_SHA:-}"
      ;;
    *)
      die "LABWC_INSTALL_METHOD must be 'source' or 'artifact', found '${LABWC_INSTALL_METHOD:-}'"
      ;;
  esac
}

patch_labwc_tweaks_login_helper() {
  local helper_path="$1"

  require_file "$helper_path"
  python3 - "$helper_path" <<'PY'
from pathlib import Path
import sys

helper_path = Path(sys.argv[1])
content = helper_path.read_text(encoding="utf-8")
old = '  [[ "$value" =~ ^[[:alnum:]_.:+ -]+$ ]] || die "invalid GTK theme name: ${value}"\n'
new = (
    '  local theme_re=\'^[[:alnum:]_.:+ -]+$\'\n'
    '  [[ "$value" =~ $theme_re ]] || die "invalid GTK theme name: ${value}"\n'
)

if old in content:
    content = content.replace(old, new, 1)

helper_path.write_text(content, encoding="utf-8")
PY
}

verify_labwc_tweaks_stage() {
  local stage_root="$1"
  local root="${stage_root%/}/usr"

  require_file "$root/bin/labwc-tweaks"
  require_file "$root/share/applications/labwc_tweaks.desktop"
  require_file "$root/share/metainfo/labwc_tweaks.appdata.xml"
  require_file "$root/share/icons/hicolor/scalable/apps/labwc_tweaks.svg"
  require_dir "$root/share/labwc-tweaks"
  require_file "$root/share/polkit-1/actions/org.labwc.labwc-tweaks.policy"
  require_file "$root/libexec/labwc-tweaks-apply-login-screen"
}

install_labwc_tweaks() {
  local work_root repo_dir build_dir stage_root provenance log_path cflags cxxflags ldflags

  validate_labwc_tweaks_settings
  log_path="$(build_log_path "labwc-tweaks-build")"
  work_root="$(fetch_source_checkout "labwc-tweaks" "$LABWC_TWEAKS_GIT_URL" "$LABWC_TWEAKS_COMMIT_SHA" "$log_path")"
  repo_dir="$work_root/source"
  build_dir="$work_root/build"
  stage_root="$work_root/stage"
  cflags="$(native_cflags)"
  cxxflags="$(native_cxxflags)"
  ldflags="$(native_ldflags)"

  trap 'cleanup_source_checkout "$work_root"' RETURN

  log_info "building labwc-tweaks from ${LABWC_TWEAKS_COMMIT_SHA}"
  run_logged_command "$log_path" env \
    CC="$(llvm_clang_bin)" \
    CXX="$(llvm_clangxx_bin)" \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    cmake -S "$repo_dir" -B "$build_dir" -G Ninja \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_C_FLAGS="$cflags" \
      -D CMAKE_CXX_FLAGS="$cxxflags" \
      -D CMAKE_EXE_LINKER_FLAGS="$ldflags" \
      -D CMAKE_SHARED_LINKER_FLAGS="$ldflags" \
      -D CMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -W no-dev
  run_logged_command "$log_path" cmake --build "$build_dir" --verbose
  run_logged_command "$log_path" env DESTDIR="$stage_root" cmake --install "$build_dir" --prefix /usr
  verify_labwc_tweaks_stage "$stage_root"

  remove_labwc_tweaks_install
  install_staged_tree "$stage_root" "$LABWC_TWEAKS_MANIFEST_PATH"
  assert_binary_dependencies "$LABWC_TWEAKS_BIN_PATH" "labwc-tweaks"
  require_file "$LABWC_TWEAKS_DESKTOP_PATH"
  require_file "$LABWC_TWEAKS_APPDATA_PATH"
  require_file "$LABWC_TWEAKS_ICON_PATH"
  require_dir "$LABWC_TWEAKS_DATA_DIR"
  require_file "$LABWC_TWEAKS_POLICY_PATH"
  require_file "$LABWC_TWEAKS_LOGIN_HELPER_PATH"
  patch_labwc_tweaks_login_helper "$LABWC_TWEAKS_LOGIN_HELPER_PATH"
  bash -n "$LABWC_TWEAKS_LOGIN_HELPER_PATH"

  provenance="$(cat <<EOF
LABWC_TWEAKS_GIT_URL="$LABWC_TWEAKS_GIT_URL"
LABWC_TWEAKS_COMMIT_SHA="$LABWC_TWEAKS_COMMIT_SHA"
LABWC_TWEAKS_INSTALL_METHOD="source"
LABWC_TWEAKS_PATCH_SERIES="patches/release/series"
LABWC_TWEAKS_CFLAGS="$cflags"
LABWC_TWEAKS_CXXFLAGS="$cxxflags"
LABWC_TWEAKS_LDFLAGS="$ldflags"
LABWC_TWEAKS_BUILD_LOG="$log_path"
LABWC_TWEAKS_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  write_source_provenance "$LABWC_TWEAKS_PROVENANCE_PATH" "$provenance"

  trap - RETURN
  cleanup_source_checkout "$work_root"
}

install_labwc_tweaks_artifact() {
  local work_root tarball_path stage_root provenance log_path

  validate_labwc_tweaks_settings
  log_path="$(build_log_path "labwc-tweaks-artifact-install")"
  work_root="$(download_release_tarball "labwc-tweaks" "$LABWC_TWEAKS_TARBALL_URL" "$LABWC_TWEAKS_TARBALL_SHA" "$log_path")"
  tarball_path="$work_root/archive.tar.gz"
  stage_root="$work_root/stage"

  trap 'cleanup_source_checkout "$work_root"' RETURN

  extract_release_tarball "$tarball_path" "$stage_root"
  verify_labwc_tweaks_stage "$stage_root"

  remove_labwc_tweaks_install
  install_staged_tree "$stage_root" "$LABWC_TWEAKS_MANIFEST_PATH"
  assert_binary_dependencies "$LABWC_TWEAKS_BIN_PATH" "labwc-tweaks"
  require_file "$LABWC_TWEAKS_DESKTOP_PATH"
  require_file "$LABWC_TWEAKS_APPDATA_PATH"
  require_file "$LABWC_TWEAKS_ICON_PATH"
  require_dir "$LABWC_TWEAKS_DATA_DIR"
  require_file "$LABWC_TWEAKS_POLICY_PATH"
  require_file "$LABWC_TWEAKS_LOGIN_HELPER_PATH"
  patch_labwc_tweaks_login_helper "$LABWC_TWEAKS_LOGIN_HELPER_PATH"
  bash -n "$LABWC_TWEAKS_LOGIN_HELPER_PATH"

  provenance="$(cat <<EOF
LABWC_TWEAKS_INSTALL_METHOD="artifact"
LABWC_TWEAKS_TARBALL_URL="$LABWC_TWEAKS_TARBALL_URL"
LABWC_TWEAKS_TARBALL_SHA="$(normalize_sha256_value "$LABWC_TWEAKS_TARBALL_SHA")"
LABWC_TWEAKS_COMMIT_TAG="$LABWC_TWEAKS_COMMIT_TAG"
LABWC_TWEAKS_COMMIT_SHA="$LABWC_TWEAKS_COMMIT_SHA"
LABWC_TWEAKS_BUILD_LOG="$log_path"
LABWC_TWEAKS_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  write_source_provenance "$LABWC_TWEAKS_PROVENANCE_PATH" "$provenance"

  trap - RETURN
  cleanup_source_checkout "$work_root"
}

remove_labwc_tweaks_install() {
  remove_manifest_install "$LABWC_TWEAKS_MANIFEST_PATH"
  remove_if_present "$LABWC_TWEAKS_BIN_PATH"
  remove_if_present "$LABWC_TWEAKS_DESKTOP_PATH"
  remove_if_present "$LABWC_TWEAKS_APPDATA_PATH"
  remove_if_present "$LABWC_TWEAKS_ICON_PATH"
  remove_if_present "$LABWC_TWEAKS_LOGIN_HELPER_PATH"
  remove_if_present "$LABWC_TWEAKS_POLICY_PATH"
  remove_if_present "$LABWC_TWEAKS_DATA_DIR"
  remove_if_present "$LABWC_TWEAKS_PROVENANCE_PATH"
  remove_if_present "$(labwc_tweaks_cache_root)"
}
