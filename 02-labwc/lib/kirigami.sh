#!/usr/bin/env bash

readonly KIRIGAMI_BUILD_LOG_NAME="kirigami-build"
readonly KIRIGAMI_RUNTIME_MANIFEST_PATH="${LABWC_SOURCE_BUILD_STATE_DIR}/kirigami-install-manifest.txt"
readonly KIRIGAMI_RUNTIME_PROVENANCE_PATH="${LABWC_SOURCE_BUILD_STATE_DIR}/kirigami-build.env"

validate_kirigami_settings() {
  require_https_url "KIRIGAMI_REPO_URL" "${KIRIGAMI_REPO_URL:-}"
  require_commit_sha "${KIRIGAMI_REPO_COMMIT:-}"
  [[ "${KIRIGAMI_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    die "KIRIGAMI_VERSION must be a semantic version, found '${KIRIGAMI_VERSION:-}'"
  }
  [[ "${KEEPSECRET_KIRIGAMI_MIN_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    die "KEEPSECRET_KIRIGAMI_MIN_VERSION must be a semantic version, found '${KEEPSECRET_KIRIGAMI_MIN_VERSION:-}'"
  }
  [[ "${KIRIGAMI_REQUIRED_QT_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    die "KIRIGAMI_REQUIRED_QT_VERSION must be a semantic version, found '${KIRIGAMI_REQUIRED_QT_VERSION:-}'"
  }
}

validate_kirigami_source_tree() {
  local repo_dir="$1"
  local declared_version=""
  local declared_qt_version=""

  require_file "$repo_dir/CMakeLists.txt"
  declared_version="$(sed -n 's/^set(KF_VERSION "\(.*\)") .*/\1/p' "$repo_dir/CMakeLists.txt" | head -n 1)"
  declared_qt_version="$(sed -n 's/^set(REQUIRED_QT_VERSION \(.*\))$/\1/p' "$repo_dir/CMakeLists.txt" | head -n 1)"

  [[ -n "$declared_version" ]] || die "could not determine Kirigami source version from $repo_dir/CMakeLists.txt"
  [[ "$declared_version" == "${KIRIGAMI_VERSION:-}" ]] || {
    die "Kirigami source version mismatch: expected '${KIRIGAMI_VERSION:-}', found '${declared_version:-unknown}'"
  }
  if [[ "$(printf '%s\n%s\n' "${KEEPSECRET_KIRIGAMI_MIN_VERSION:-}" "$declared_version" | sort -V | head -n 1)" != "${KEEPSECRET_KIRIGAMI_MIN_VERSION:-}" ]]; then
    die "Kirigami source version '${declared_version}' is older than required minimum '${KEEPSECRET_KIRIGAMI_MIN_VERSION:-}'"
  fi
  [[ "$declared_qt_version" == "${KIRIGAMI_REQUIRED_QT_VERSION:-}" ]] || {
    die "Kirigami required Qt version mismatch: expected '${KIRIGAMI_REQUIRED_QT_VERSION:-}', found '${declared_qt_version:-unknown}'"
  }
}

strip_kirigami_devel_artifacts() {
  local stage_root="$1"

  remove_if_present "$stage_root/usr/local/include"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    remove_if_present "$path"
  done < <(find "$stage_root/usr/local" -type d \( -path '*/cmake/*' -o -path '*/ECM/*' \) 2>/dev/null | LC_ALL=C sort -r)
}

verify_kirigami_runtime_stage() {
  local stage_root="$1"
  local qml_qmldir=""
  local runtime_library=""

  qml_qmldir="$(find "$stage_root/usr/local" -path '*/qt6/qml/org/kde/kirigami/qmldir' -type f | LC_ALL=C sort | head -n 1)"
  [[ -n "$qml_qmldir" ]] || die "Kirigami runtime stage is missing the org.kde.kirigami qmldir"
  runtime_library="$(find "$stage_root/usr/local" -type f \( -name 'libKirigami*.so*' -o -name 'libKF6Kirigami*.so*' \) | LC_ALL=C sort | head -n 1)"
  [[ -n "$runtime_library" ]] || die "Kirigami runtime stage is missing a shared library payload"
}

install_kirigami_runtime_stage() {
  local stage_root="$1"
  local provenance="$2"

  verify_kirigami_runtime_stage "$stage_root"
  strip_kirigami_devel_artifacts "$stage_root"
  install_staged_tree "$stage_root" "$KIRIGAMI_RUNTIME_MANIFEST_PATH"
  write_source_provenance "$KIRIGAMI_RUNTIME_PROVENANCE_PATH" "$provenance"
}

remove_kirigami_runtime_install() {
  remove_manifest_install "$KIRIGAMI_RUNTIME_MANIFEST_PATH"
  remove_if_present "$KIRIGAMI_RUNTIME_PROVENANCE_PATH"
}

build_kirigami_prefix() {
  local work_root repo_dir build_dir prefix_dir log_path cflags cxxflags ldflags
  local ecm_work_root ecm_prefix cmake_prefix_path ecm_dir

  validate_kirigami_settings
  validate_ecm_settings
  log_path="$(build_log_path "$KIRIGAMI_BUILD_LOG_NAME")"
  work_root="$(fetch_source_checkout "kirigami" "$KIRIGAMI_REPO_URL" "$KIRIGAMI_REPO_COMMIT" "$log_path")"
  repo_dir="$work_root/source"
  build_dir="$work_root/build"
  prefix_dir="$work_root/stage/usr/local"
  cflags="$(native_cflags)"
  cxxflags="$(native_cxxflags)"
  ldflags="$(native_ldflags)"
  ecm_work_root="$(build_ecm_prefix)"
  ecm_prefix="$ecm_work_root/prefix"
  cmake_prefix_path="$ecm_prefix"
  ecm_dir="$ecm_prefix/share/ECM/cmake"
  validate_kirigami_source_tree "$repo_dir"

  trap 'cleanup_source_checkout "$ecm_work_root"' RETURN

  run_logged_command "$log_path" env \
    PATH="$ecm_prefix/bin:$PATH" \
    CC="$(llvm_clang_bin)" \
    CXX="$(llvm_clangxx_bin)" \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    CMAKE_PREFIX_PATH="$cmake_prefix_path" \
    cmake -S "$repo_dir" -B "$build_dir" -G Ninja \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=/usr/local \
      -D CMAKE_C_FLAGS="$cflags" \
      -D CMAKE_CXX_FLAGS="$cxxflags" \
      -D CMAKE_EXE_LINKER_FLAGS="$ldflags" \
      -D CMAKE_SHARED_LINKER_FLAGS="$ldflags" \
      -D CMAKE_PREFIX_PATH="$cmake_prefix_path" \
      -D ECM_DIR="$ecm_dir" \
      -D BUILD_TESTING=OFF \
      -D BUILD_EXAMPLES=OFF \
      -D CMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -W no-dev
  run_logged_command "$log_path" cmake --build "$build_dir" --verbose
  run_logged_command "$log_path" env DESTDIR="$work_root/stage" cmake --install "$build_dir" --prefix /usr/local

  trap - RETURN
  cleanup_source_checkout "$ecm_work_root"
  printf '%s\n' "$work_root"
}
