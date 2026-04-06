#!/usr/bin/env bash

readonly ECM_BUILD_LOG_NAME="ecm-build"

validate_ecm_settings() {
  require_https_url "ECM_REPO_URL" "${ECM_REPO_URL:-}"
  require_commit_sha "${ECM_REPO_COMMIT:-}"
  [[ "${ECM_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    die "ECM_VERSION must be a semantic version, found '${ECM_VERSION:-}'"
  }
  [[ "${ECM_REQUIRED_CMAKE_VERSION:-}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
    die "ECM_REQUIRED_CMAKE_VERSION must be a cmake version, found '${ECM_REQUIRED_CMAKE_VERSION:-}'"
  }
}

validate_ecm_source_tree() {
  local repo_dir="$1"
  local declared_version=""
  local declared_cmake_version=""

  require_file "$repo_dir/CMakeLists.txt"
  declared_version="$(sed -n 's/^set(VERSION "\(.*\)") .*/\1/p' "$repo_dir/CMakeLists.txt" | head -n 1)"
  declared_cmake_version="$(sed -n 's/^cmake_minimum_required(VERSION \(.*\))$/\1/p' "$repo_dir/CMakeLists.txt" | head -n 1)"
  [[ "$declared_version" == "${ECM_VERSION:-}" ]] || {
    die "ECM source version mismatch: expected '${ECM_VERSION:-}', found '${declared_version:-unknown}'"
  }
  [[ "$declared_cmake_version" == "${ECM_REQUIRED_CMAKE_VERSION:-}" ]] || {
    die "ECM cmake requirement mismatch: expected '${ECM_REQUIRED_CMAKE_VERSION:-}', found '${declared_cmake_version:-unknown}'"
  }
}

build_ecm_prefix() {
  local work_root repo_dir build_dir prefix_dir log_path cflags cxxflags ldflags

  validate_ecm_settings
  log_path="$(build_log_path "$ECM_BUILD_LOG_NAME")"
  work_root="$(fetch_source_checkout "extra-cmake-modules" "$ECM_REPO_URL" "$ECM_REPO_COMMIT" "$log_path")"
  repo_dir="$work_root/source"
  build_dir="$work_root/build"
  prefix_dir="$work_root/prefix"
  cflags="$(native_cflags)"
  cxxflags="$(native_cxxflags)"
  ldflags="$(native_ldflags)"
  validate_ecm_source_tree "$repo_dir"
  run_cmd rm -rf -- "$prefix_dir"

  run_logged_command "$log_path" env \
    CC="$(llvm_clang_bin)" \
    CXX="$(llvm_clangxx_bin)" \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    cmake -S "$repo_dir" -B "$build_dir" -G Ninja \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX="$prefix_dir" \
      -D CMAKE_POSITION_INDEPENDENT_CODE=ON \
      -D CMAKE_C_FLAGS="$cflags" \
      -D CMAKE_CXX_FLAGS="$cxxflags" \
      -D CMAKE_EXE_LINKER_FLAGS="$ldflags" \
      -D CMAKE_SHARED_LINKER_FLAGS="$ldflags" \
      -D CMAKE_MODULE_LINKER_FLAGS="$ldflags" \
      -D CMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -D BUILD_TESTING=OFF \
      -W no-dev
  run_logged_command "$log_path" cmake --build "$build_dir" --verbose
  run_logged_command "$log_path" cmake --install "$build_dir"

  printf '%s\n' "$work_root"
}
