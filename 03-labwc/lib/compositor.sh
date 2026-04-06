#!/usr/bin/env bash

readonly WLROOTS_MANIFEST_PATH="${LABWC_SOURCE_BUILD_STATE_DIR}/wlroots-install-manifest.txt"
readonly WLROOTS_PROVENANCE_PATH="${LABWC_SOURCE_BUILD_STATE_DIR}/wlroots-build.env"
readonly LABWC_MANAGED_MANIFEST_PATH="${LABWC_SOURCE_BUILD_STATE_DIR}/labwc-install-manifest.txt"
readonly LABWC_MANAGED_PROVENANCE_PATH="${LABWC_SOURCE_BUILD_STATE_DIR}/labwc-build.env"

managed_labwc_binary_path() {
  if [[ "${LABWC_INSTALL_METHOD:-artifact}" == "source" ]]; then
    printf '%s\n' "/usr/local/bin/labwc"
    return 0
  fi
  printf '%s\n' "/usr/bin/labwc"
}

validate_labwc_stack_settings() {
  require_safe_token "LABWC_SOURCE_PACKAGE" "${LABWC_SOURCE_PACKAGE:-}"
}

local_pkg_config_path() {
  printf '%s\n' "/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
}

meson_project_version() {
  local meson_build_path="$1"
  python3 - "$meson_build_path" <<'PY'
from pathlib import Path
import re
import sys

content = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"version:\s*'([^']+)'", content)
if not match:
    raise SystemExit(f"could not parse Meson project version from {sys.argv[1]}")
print(match.group(1), end="")
PY
}

labwc_required_wlroots_dependency() {
  local repo_dir="$1"
  python3 - "$repo_dir/meson.build" <<'PY'
from pathlib import Path
import re
import sys

content = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"wlroots\s*=\s*dependency\(\s*'([^']+)'", content, re.S)
if not match:
    raise SystemExit(f"could not parse wlroots dependency name from {sys.argv[1]}")
print(match.group(1), end="")
PY
}

load_arg_lines() {
  local -n output_ref="$1"
  local arg_source="$2"
  local arg_line=""

  output_ref=()
  while IFS= read -r arg_line; do
    [[ -n "$arg_line" ]] || continue
    output_ref+=("$arg_line")
  done <<<"$arg_source"
}

labwc_meson_args() {
  cat <<'EOF'
--buildtype=release
-Db_ndebug=true
-Db_pie=true
-Db_lto=true
-Db_lto_mode=thin
-Dxwayland=enabled
-Dman-pages=enabled
-Dsvg=enabled
-Dicon=enabled
-Dlabnag=disabled
-Dnls=enabled
-Dtest=disabled
-Dstatic_analyzer=disabled
-Dsections=disabled
EOF
}

verify_labwc_stage() {
  local stage_root="$1"
  local root="${stage_root%/}/usr/local"

  require_file "$root/bin/labwc"
  require_file "$root/share/xdg-desktop-portal/labwc-portals.conf"
  require_file "$root/share/icons/hicolor/scalable/apps/labwc.svg"
}

remove_wlroots_source_install() {
  remove_manifest_install "$WLROOTS_MANIFEST_PATH"
  remove_if_present "$WLROOTS_PROVENANCE_PATH"
  run_cmd ldconfig >/dev/null 2>&1 || true
}

remove_labwc_source_install() {
  remove_manifest_install "$LABWC_MANAGED_MANIFEST_PATH"
  remove_if_present "$LABWC_MANAGED_PROVENANCE_PATH"
}

install_labwc_stack_from_source() {
  local labwc_work_root=""
  local labwc_repo_dir=""
  local required_wlroots_dep=""
  local selected_labwc_source_version=""
  local labwc_log_path=""
  local labwc_build_dir=""
  local labwc_stage_root=""
  local cflags=""
  local cxxflags=""
  local ldflags=""
  local pkg_config_path=""
  local -a labwc_args=()
  local labwc_provenance=""
  local resolved_wlroots_version=""
  local suite=""

  validate_labwc_stack_settings
  ensure_source_state_dir
  suite="$(debian_suite_value)"
  labwc_log_path="$(build_log_path "labwc-build")"

  labwc_work_root="$(fetch_debian_source_checkout "labwc" "$LABWC_SOURCE_PACKAGE" "$suite" "$labwc_log_path")"
  labwc_repo_dir="$(debian_source_tree_path "$labwc_work_root/source" "$LABWC_SOURCE_PACKAGE")"

  trap 'cleanup_source_checkout "$labwc_work_root"' RETURN

  required_wlroots_dep="$(labwc_required_wlroots_dependency "$labwc_repo_dir")"
  selected_labwc_source_version="$(debian_source_version "$labwc_repo_dir")"
  remove_wlroots_source_install
  pkg-config --exists "$required_wlroots_dep" || die "pkg-config cannot resolve required wlroots dependency '$required_wlroots_dep'; ensure apt-get build-dep -t ${suite} ${LABWC_SOURCE_PACKAGE} installed the backports wlroots development package"
  resolved_wlroots_version="$(pkg-config --modversion "$required_wlroots_dep" 2>/dev/null || true)"
  [[ -n "$resolved_wlroots_version" ]] || die "pkg-config did not return a version for required wlroots dependency '$required_wlroots_dep'"

  cflags="$(native_cflags)"
  cxxflags="$(native_cxxflags)"
  ldflags="$(native_ldflags)"
  pkg_config_path="$(local_pkg_config_path)"
  load_arg_lines labwc_args "$(labwc_meson_args)"

  log_info "building labwc from Debian source package ${LABWC_SOURCE_PACKAGE} (${selected_labwc_source_version}) against packaged ${required_wlroots_dep} ${resolved_wlroots_version}"
  labwc_build_dir="$labwc_work_root/build"
  labwc_stage_root="$labwc_work_root/stage"
  run_cmd rm -rf -- "$labwc_build_dir" "$labwc_stage_root"
  run_logged_command "$labwc_log_path" env \
    CC="$(llvm_clang_bin)" \
    CXX="$(llvm_clangxx_bin)" \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    PKG_CONFIG_PATH="$pkg_config_path" \
    meson setup "$labwc_build_dir" "$labwc_repo_dir" "${labwc_args[@]}"
  run_logged_command "$labwc_log_path" env \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    PKG_CONFIG_PATH="$pkg_config_path" \
    meson compile -C "$labwc_build_dir"
  run_logged_command "$labwc_log_path" env \
    DESTDIR="$labwc_stage_root" \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    PKG_CONFIG_PATH="$pkg_config_path" \
    meson install -C "$labwc_build_dir" --no-rebuild
  remove_if_present "$labwc_stage_root/usr/local/share/wayland-sessions/labwc.desktop"
  verify_labwc_stage "$labwc_stage_root"
  remove_labwc_source_install
  install_staged_tree "$labwc_stage_root" "$LABWC_MANAGED_MANIFEST_PATH"
  assert_binary_dependencies "$(managed_labwc_binary_path)" "labwc"
  "$(managed_labwc_binary_path)" --version >/dev/null 2>&1 || die "labwc --version failed after source install"

  labwc_provenance="$(cat <<EOF
LABWC_SOURCE_PACKAGE="$LABWC_SOURCE_PACKAGE"
LABWC_SOURCE_SUITE="$suite"
LABWC_SOURCE_VERSION="$selected_labwc_source_version"
LABWC_VERSION="$(meson_project_version "$labwc_repo_dir/meson.build")"
LABWC_RESOLVED_WLROOTS_DEPENDENCY="$required_wlroots_dep"
LABWC_RESOLVED_WLROOTS_VERSION="$resolved_wlroots_version"
LABWC_CFLAGS="$cflags"
LABWC_CXXFLAGS="$cxxflags"
LABWC_LDFLAGS="$ldflags"
LABWC_BUILD_LOG="$labwc_log_path"
LABWC_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  write_source_provenance "$LABWC_MANAGED_PROVENANCE_PATH" "$labwc_provenance"

  trap - RETURN
  cleanup_source_checkout "$labwc_work_root"
}
