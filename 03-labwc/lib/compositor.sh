#!/usr/bin/env bash

readonly WLROOTS_UPSTREAM_REPO_URL="https://gitlab.freedesktop.org/wlroots/wlroots.git"
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
  require_https_url "WLROOTS_REPO_URL" "${WLROOTS_REPO_URL:-}"
  require_commit_sha "${WLROOTS_COMMIT_SHA:-}"
  require_https_url "LABWC_REPO_URL" "${LABWC_REPO_URL:-}"
  require_commit_sha "${LABWC_COMMIT_SHA:-}"
}

require_git_ref() {
  local label="$1"
  local value="$2"
  [[ -n "$value" ]] || die "$label must not be empty"
  [[ "$value" != *" "* ]] || die "$label must not contain spaces: '$value'"
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

wlroots_dependency_name_from_version() {
  local version="$1"
  local major_minor=""

  [[ "$version" =~ ^([0-9]+\.[0-9]+) ]] || die "wlroots version must begin with major.minor, found '$version'"
  major_minor="${BASH_REMATCH[1]}"
  printf 'wlroots-%s\n' "$major_minor"
}

wrap_file_value() {
  local wrap_path="$1"
  local section_name="$2"
  local key_name="$3"

  python3 - "$wrap_path" "$section_name" "$key_name" <<'PY'
from pathlib import Path
import configparser
import sys

config = configparser.ConfigParser(interpolation=None)
config.read_string(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(config[sys.argv[2]][sys.argv[3]], end="")
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

wlroots_branch_from_dependency_name() {
  local dependency_name="$1"

  [[ "$dependency_name" =~ ^wlroots-([0-9]+\.[0-9]+)$ ]] || {
    die "cannot derive wlroots branch from dependency name '$dependency_name'"
  }
  printf '%s\n' "${BASH_REMATCH[1]}"
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

wlroots_meson_args() {
  cat <<'EOF'
--buildtype=release
--wrap-mode=nodownload
--force-fallback-for=pixman
-Db_ndebug=true
-Ddefault_library=shared
-Db_lto=true
-Db_lto_mode=thin
-Dwerror=false
-Dexamples=false
-Dbackends=drm,libinput
-Drenderers=gles2
-Dallocators=gbm
-Dsession=enabled
-Dxwayland=enabled
-Dcolor-management=disabled
-Dlibliftoff=enabled
-Dxcb-errors=enabled
EOF
}

labwc_meson_args() {
  cat <<'EOF'
--buildtype=release
--wrap-mode=nodownload
-Db_ndebug=true
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

verify_wlroots_stage() {
  local stage_root="$1"
  local pkgconfig_path=""

  pkgconfig_path="$(find "$stage_root" -type f -path '*/pkgconfig/wlroots-*.pc' | LC_ALL=C sort | head -n 1)"
  [[ -n "$pkgconfig_path" ]] || die "wlroots staged install is missing a pkg-config file"
  require_file "$pkgconfig_path"
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
  local wlroots_work_root=""
  local wlroots_repo_dir=""
  local requested_wlroots_audit_root=""
  local required_wlroots_dep=""
  local required_wlroots_branch=""
  local selected_wlroots_url=""
  local selected_wlroots_ref=""
  local selected_wlroots_commit=""
  local selected_wlroots_version=""
  local selected_wlroots_dep=""
  local selected_wlroots_source="requested"
  local requested_wlroots_version=""
  local requested_wlroots_dep=""
  local compatibility_note=""
  local requested_matches_expected=0
  local wlroots_log_path=""
  local labwc_log_path=""
  local wlroots_build_dir=""
  local wlroots_stage_root=""
  local labwc_build_dir=""
  local labwc_stage_root=""
  local cflags=""
  local cxxflags=""
  local ldflags=""
  local pkg_config_path=""
  local -a wlroots_args=()
  local -a labwc_args=()
  local wlroots_provenance=""
  local labwc_provenance=""

  validate_labwc_stack_settings
  ensure_source_state_dir
  wlroots_log_path="$(build_log_path "wlroots-build")"
  labwc_log_path="$(build_log_path "labwc-build")"

  labwc_work_root="$(fetch_source_checkout "labwc" "$LABWC_REPO_URL" "$LABWC_COMMIT_SHA" "$labwc_log_path")"
  labwc_repo_dir="$labwc_work_root/source"

  trap 'cleanup_source_checkout "$labwc_work_root"; cleanup_source_checkout "$wlroots_work_root"; cleanup_source_checkout "$requested_wlroots_audit_root"' RETURN

  required_wlroots_dep="$(labwc_required_wlroots_dependency "$labwc_repo_dir")"
  required_wlroots_branch="$(wlroots_branch_from_dependency_name "$required_wlroots_dep")"

  log_info "auditing requested wlroots source ${WLROOTS_COMMIT_SHA} for labwc dependency ${required_wlroots_dep}"
  requested_wlroots_audit_root="$(fetch_source_checkout "wlroots" "$WLROOTS_REPO_URL" "$WLROOTS_COMMIT_SHA" "$wlroots_log_path")"
  requested_wlroots_version="$(meson_project_version "$requested_wlroots_audit_root/source/meson.build")"
  requested_wlroots_dep="$(wlroots_dependency_name_from_version "$requested_wlroots_version")"

  if [[ "$requested_wlroots_dep" == "$required_wlroots_dep" ]]; then
    requested_matches_expected=1
    selected_wlroots_url="$WLROOTS_REPO_URL"
    selected_wlroots_ref="$WLROOTS_COMMIT_SHA"
    wlroots_work_root="$requested_wlroots_audit_root"
    wlroots_repo_dir="$wlroots_work_root/source"
    requested_wlroots_audit_root=""
  else
    selected_wlroots_source="freedesktop-upstream-branch"
    selected_wlroots_url="$WLROOTS_UPSTREAM_REPO_URL"
    selected_wlroots_ref="$required_wlroots_branch"
    compatibility_note="requested wlroots ${requested_wlroots_version} exposes ${requested_wlroots_dep}, but labwc ${LABWC_COMMIT_SHA} requires ${required_wlroots_dep}; using freedesktop wlroots branch ${required_wlroots_branch}"
    log_warn "$compatibility_note"
    requested_wlroots_audit_root=""
    wlroots_work_root="$(fetch_source_ref_checkout "wlroots" "$selected_wlroots_url" "$selected_wlroots_ref" "$wlroots_log_path")"
    wlroots_repo_dir="$wlroots_work_root/source"
  fi

  selected_wlroots_commit="$(run_git_in_checkout "$wlroots_repo_dir" rev-parse HEAD)"
  selected_wlroots_version="$(meson_project_version "$wlroots_repo_dir/meson.build")"
  selected_wlroots_dep="$(wlroots_dependency_name_from_version "$selected_wlroots_version")"
  [[ "$selected_wlroots_dep" == "$required_wlroots_dep" ]] || {
    die "selected wlroots source '${selected_wlroots_version}' exposes '${selected_wlroots_dep}', but labwc requires '${required_wlroots_dep}'"
  }

  cflags="$(native_cflags)"
  cxxflags="$(native_cxxflags)"
  ldflags="$(native_ldflags)"
  pkg_config_path="$(local_pkg_config_path)"
  load_arg_lines wlroots_args "$(wlroots_meson_args)"
  load_arg_lines labwc_args "$(labwc_meson_args)"

  log_info "building wlroots from ${selected_wlroots_commit} (${selected_wlroots_source})"
  wlroots_build_dir="$wlroots_work_root/build"
  wlroots_stage_root="$wlroots_work_root/stage"
  run_cmd rm -rf -- "$wlroots_build_dir" "$wlroots_stage_root"
  run_logged_command "$wlroots_log_path" bash -lc '
    set -euo pipefail
    cd "$1"
    if [[ -d subprojects ]]; then
      meson subprojects download
    fi
  ' bash "$wlroots_repo_dir"
  run_logged_command "$wlroots_log_path" env \
    CC="$(llvm_clang_bin)" \
    CXX="$(llvm_clangxx_bin)" \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    PKG_CONFIG_PATH="$pkg_config_path" \
    meson setup "$wlroots_build_dir" "$wlroots_repo_dir" "${wlroots_args[@]}"
  run_logged_command "$wlroots_log_path" env \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    PKG_CONFIG_PATH="$pkg_config_path" \
    meson compile -C "$wlroots_build_dir"
  run_logged_command "$wlroots_log_path" env \
    DESTDIR="$wlroots_stage_root" \
    CFLAGS="$cflags" \
    CXXFLAGS="$cxxflags" \
    LDFLAGS="$ldflags" \
    PKG_CONFIG_PATH="$pkg_config_path" \
    meson install -C "$wlroots_build_dir" --no-rebuild
  verify_wlroots_stage "$wlroots_stage_root"
  remove_wlroots_source_install
  install_staged_tree "$wlroots_stage_root" "$WLROOTS_MANIFEST_PATH"
  run_cmd ldconfig

  wlroots_provenance="$(cat <<EOF
WLROOTS_REQUESTED_REPO_URL="$WLROOTS_REPO_URL"
WLROOTS_REQUESTED_COMMIT_SHA="$WLROOTS_COMMIT_SHA"
WLROOTS_REQUESTED_VERSION="$requested_wlroots_version"
WLROOTS_REQUESTED_DEPENDENCY="$requested_wlroots_dep"
WLROOTS_SELECTED_SOURCE="$selected_wlroots_source"
WLROOTS_SELECTED_REPO_URL="$selected_wlroots_url"
WLROOTS_SELECTED_REF="$selected_wlroots_ref"
WLROOTS_SELECTED_COMMIT_SHA="$selected_wlroots_commit"
WLROOTS_SELECTED_VERSION="$selected_wlroots_version"
WLROOTS_REQUIRED_DEPENDENCY="$required_wlroots_dep"
WLROOTS_REQUIRED_BRANCH="$required_wlroots_branch"
WLROOTS_CFLAGS="$cflags"
WLROOTS_CXXFLAGS="$cxxflags"
WLROOTS_LDFLAGS="$ldflags"
WLROOTS_BUILD_LOG="$wlroots_log_path"
WLROOTS_COMPATIBILITY_NOTE="$compatibility_note"
WLROOTS_INSTALLED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF
)"
  write_source_provenance "$WLROOTS_PROVENANCE_PATH" "$wlroots_provenance"

  log_info "building labwc from ${LABWC_COMMIT_SHA} against ${selected_wlroots_dep}"
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
LABWC_REPO_URL="$LABWC_REPO_URL"
LABWC_COMMIT_SHA="$LABWC_COMMIT_SHA"
LABWC_VERSION="$(meson_project_version "$labwc_repo_dir/meson.build")"
LABWC_REQUIRED_WLROOTS_DEPENDENCY="$required_wlroots_dep"
LABWC_REQUIRED_WLROOTS_BRANCH="$required_wlroots_branch"
LABWC_SELECTED_WLROOTS_SOURCE="$selected_wlroots_source"
LABWC_SELECTED_WLROOTS_URL="$selected_wlroots_url"
LABWC_SELECTED_WLROOTS_REF="$selected_wlroots_ref"
LABWC_SELECTED_WLROOTS_COMMIT_SHA="$selected_wlroots_commit"
LABWC_SELECTED_WLROOTS_VERSION="$selected_wlroots_version"
LABWC_REQUESTED_WLROOTS_MATCHES_EXPECTED="$requested_matches_expected"
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
  cleanup_source_checkout "$wlroots_work_root"
}
