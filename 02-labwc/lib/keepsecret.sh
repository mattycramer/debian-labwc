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
  case "${LABWC_INSTALL_METHOD:-}" in
    source)
      require_https_url "KEEPSECRET_GIT_URL" "${KEEPSECRET_GIT_URL:-}"
      require_commit_sha "${KEEPSECRET_COMMIT_SHA:-}"
      ;;
    artifact)
      require_https_url "KEEPSECRET_TARBALL_URL" "${KEEPSECRET_TARBALL_URL:-}"
      require_sha256_hex "$(normalize_sha256_value "${KEEPSECRET_TARBALL_SHA:-}")"
      require_safe_token "KEEPSECRET_COMMIT_TAG" "${KEEPSECRET_COMMIT_TAG:-}"
      require_commit_sha "${KEEPSECRET_COMMIT_SHA:-}"
      ;;
    *)
      die "LABWC_INSTALL_METHOD must be 'source' or 'artifact', found '${LABWC_INSTALL_METHOD:-}'"
      ;;
  esac
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
  local work_root repo_dir build_dir stage_root provenance log_path cflags cxxflags ldflags
  local kirigami_work_root kirigami_prefix kirigami_provenance
  local ecm_work_root ecm_prefix ecm_dir cmake_prefix_env cmake_prefix_arg

  validate_keepsecret_settings
  validate_kirigami_settings
  validate_ecm_settings
  log_path="$(build_log_path "keepsecret-build")"
  work_root="$(fetch_source_checkout "keepsecret" "$KEEPSECRET_GIT_URL" "$KEEPSECRET_COMMIT_SHA" "$log_path")"
  repo_dir="$work_root/source"
  build_dir="$work_root/build"
  stage_root="$work_root/stage"
  cflags="$(native_cflags)"
  cxxflags="$(native_cxxflags)"
  ldflags="$(native_ldflags)"
  kirigami_work_root="$(build_kirigami_prefix)"
  kirigami_prefix="$kirigami_work_root/stage/usr/local"
  ecm_work_root="$(build_ecm_prefix)"
  ecm_prefix="$ecm_work_root/prefix"
  ecm_dir="$ecm_prefix/share/ECM/cmake"
  cmake_prefix_env="${kirigami_prefix}:${ecm_prefix}"
  cmake_prefix_arg="${kirigami_prefix};${ecm_prefix}"

  trap 'cleanup_source_checkout "$work_root"; cleanup_source_checkout "$kirigami_work_root"; cleanup_source_checkout "$ecm_work_root"' RETURN

  log_info "building keepsecret from ${KEEPSECRET_COMMIT_SHA}"
  run_logged_command "$log_path" env \
    CC="$(llvm_clang_bin)" \
    CXX="$(llvm_clangxx_bin)" \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    PATH="$ecm_prefix/bin:$PATH" \
    CMAKE_PREFIX_PATH="$cmake_prefix_env" \
    ECM_DIR="$ecm_dir" \
    cmake -S "$repo_dir" -B "$build_dir" -G Ninja \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=/usr/local \
      -D CMAKE_C_FLAGS="$cflags" \
      -D CMAKE_CXX_FLAGS="$cxxflags" \
      -D CMAKE_EXE_LINKER_FLAGS="$ldflags" \
      -D CMAKE_SHARED_LINKER_FLAGS="$ldflags" \
      -D CMAKE_PREFIX_PATH="$cmake_prefix_arg" \
      -D ECM_DIR="$ecm_dir" \
      -D CMAKE_INTERPROCEDURAL_OPTIMIZATION=ON
  run_logged_command "$log_path" cmake --build "$build_dir" --verbose
  run_logged_command "$log_path" env DESTDIR="$stage_root" cmake --install "$build_dir" --prefix /usr/local
  verify_keepsecret_stage "$stage_root"

  kirigami_provenance="$(cat <<EOF
KIRIGAMI_REPO_URL="$KIRIGAMI_REPO_URL"
KIRIGAMI_REPO_COMMIT="$KIRIGAMI_REPO_COMMIT"
KIRIGAMI_VERSION="$KIRIGAMI_VERSION"
KEEPSECRET_KIRIGAMI_MIN_VERSION="$KEEPSECRET_KIRIGAMI_MIN_VERSION"
KIRIGAMI_REQUIRED_QT_VERSION="$KIRIGAMI_REQUIRED_QT_VERSION"
ECM_REPO_URL="$ECM_REPO_URL"
ECM_REPO_COMMIT="$ECM_REPO_COMMIT"
ECM_VERSION="$ECM_VERSION"
LABWC_LLVM_UPSTREAM_MAJOR="$LABWC_LLVM_UPSTREAM_MAJOR"
LABWC_LLVM_UPSTREAM_VERSION="$LABWC_LLVM_UPSTREAM_VERSION"
KIRIGAMI_BUILD_LOG="$(build_log_path "$KIRIGAMI_BUILD_LOG_NAME")"
KIRIGAMI_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  remove_kirigami_runtime_install
  install_kirigami_runtime_stage "$kirigami_work_root/stage" "$kirigami_provenance"

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
KEEPSECRET_INSTALL_METHOD="source"
KIRIGAMI_REPO_URL="$KIRIGAMI_REPO_URL"
KIRIGAMI_REPO_COMMIT="$KIRIGAMI_REPO_COMMIT"
ECM_REPO_URL="$ECM_REPO_URL"
ECM_REPO_COMMIT="$ECM_REPO_COMMIT"
KEEPSECRET_CMAKE_PREFIX_PATH="$cmake_prefix_arg"
KEEPSECRET_ECM_DIR="$ecm_dir"
KEEPSECRET_PATCH_SERIES="patches/release/series"
KEEPSECRET_CFLAGS="$cflags"
KEEPSECRET_CXXFLAGS="$cxxflags"
KEEPSECRET_LDFLAGS="$ldflags"
KEEPSECRET_BUILD_LOG="$log_path"
KEEPSECRET_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  write_source_provenance "$KEEPSECRET_PROVENANCE_PATH" "$provenance"

  trap - RETURN
  cleanup_source_checkout "$work_root"
  cleanup_source_checkout "$kirigami_work_root"
  cleanup_source_checkout "$ecm_work_root"
}

install_keepsecret_artifact() {
  local work_root tarball_path stage_root provenance log_path

  validate_keepsecret_settings
  log_path="$(build_log_path "keepsecret-artifact-install")"
  work_root="$(download_release_tarball "keepsecret" "$KEEPSECRET_TARBALL_URL" "$KEEPSECRET_TARBALL_SHA" "$log_path")"
  tarball_path="$work_root/archive.tar.gz"
  stage_root="$work_root/stage"

  trap 'cleanup_source_checkout "$work_root"' RETURN

  extract_release_tarball "$tarball_path" "$stage_root"
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
KEEPSECRET_INSTALL_METHOD="artifact"
KEEPSECRET_TARBALL_URL="$KEEPSECRET_TARBALL_URL"
KEEPSECRET_TARBALL_SHA="$(normalize_sha256_value "$KEEPSECRET_TARBALL_SHA")"
KEEPSECRET_COMMIT_TAG="$KEEPSECRET_COMMIT_TAG"
KEEPSECRET_COMMIT_SHA="$KEEPSECRET_COMMIT_SHA"
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
