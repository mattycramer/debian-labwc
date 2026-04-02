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
readonly LABWC_TWEAKS_TMP_ROOT_PREFIX="/tmp/labwc-tweaks"

labwc_tweaks_cache_root() {
  printf '%s/.cache/labwc-session/labwc-tweaks\n' "$LABWC_TARGET_HOME"
}

labwc_tweaks_work_root() {
  printf '%s-%s\n' "$LABWC_TWEAKS_TMP_ROOT_PREFIX" "$LABWC_TARGET_USER"
}

validate_labwc_tweaks_settings() {
  [[ "${GITHUB_LABWC_TAG:-}" =~ ^[A-Za-z0-9._-]+$ ]] || {
    die "GITHUB_LABWC_TAG must contain only alnum, dot, underscore, or dash, found '${GITHUB_LABWC_TAG:-}'"
  }
  [[ "${GITHUB_LABWC_URL:-}" =~ ^https://github\.com/[^/]+/[^/]+/releases/download/${GITHUB_LABWC_TAG}/[^/?#]+\.tar\.gz$ ]] || {
    die "GITHUB_LABWC_URL must be a GitHub release tarball for tag '${GITHUB_LABWC_TAG}', found '${GITHUB_LABWC_URL:-}'"
  }
  [[ "${GITHUB_LABWC_TARBALL_SHA:-}" =~ ^[0-9a-f]{64}$ ]] || {
    die "GITHUB_LABWC_TARBALL_SHA must be a 64 character lowercase hex sha256, found '${GITHUB_LABWC_TARBALL_SHA:-}'"
  }
  [[ "${GITHUB_LABWC_COMMIT_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || {
    die "GITHUB_LABWC_COMMIT_SHA must be a 40 character lowercase hex commit sha, found '${GITHUB_LABWC_COMMIT_SHA:-}'"
  }
}

install_labwc_tweaks() {
  local work_root tarball_path extract_root

  validate_labwc_tweaks_settings
  work_root="$(labwc_tweaks_work_root)"
  tarball_path="${work_root}/labwc-tweaks.tar.gz"
  extract_root="${work_root}/extract"

  [[ "$work_root" == /tmp/* ]] || die "labwc-tweaks work root must stay under /tmp: $work_root"
  remove_if_present "$work_root"
  run_cmd install -d -m 0755 "$work_root"

  log_info "installing labwc-tweaks ${GITHUB_LABWC_TAG} (${GITHUB_LABWC_COMMIT_SHA})"
  download_release_tarball "labwc-tweaks" "$GITHUB_LABWC_URL" "$GITHUB_LABWC_TARBALL_SHA" "$tarball_path"
  extract_release_payload_tree "labwc-tweaks" "$tarball_path" "usr" "$extract_root"
  remove_labwc_tweaks_install
  install_release_payload_tree "$extract_root" "$LABWC_TWEAKS_MANIFEST_PATH"
  assert_release_binary_dependencies "$LABWC_TWEAKS_BIN_PATH" "labwc-tweaks"
  "$LABWC_TWEAKS_BIN_PATH" --version >/dev/null 2>&1 || die "installed labwc-tweaks binary failed the --version self-test"
  remove_if_present "$work_root"
}

remove_labwc_tweaks_install() {
  remove_release_manifest_install "$LABWC_TWEAKS_MANIFEST_PATH"
  remove_if_present "$LABWC_TWEAKS_BIN_PATH"
  remove_if_present "$LABWC_TWEAKS_DESKTOP_PATH"
  remove_if_present "$LABWC_TWEAKS_APPDATA_PATH"
  remove_if_present "$LABWC_TWEAKS_ICON_PATH"
  remove_if_present "$LABWC_TWEAKS_LOGIN_HELPER_PATH"
  remove_if_present "$LABWC_TWEAKS_POLICY_PATH"
  remove_if_present "$LABWC_TWEAKS_DATA_DIR"
  remove_if_present "$(labwc_tweaks_cache_root)"
}
