#!/usr/bin/env bash

readonly KEEPSECRET_BIN_PATH="/usr/local/bin/keepsecret"
readonly KEEPSECRET_DESKTOP_PATH="/usr/local/share/applications/org.kde.keepsecret.desktop"
readonly KEEPSECRET_APPDATA_PATH="/usr/local/share/metainfo/org.kde.keepsecret.metainfo.xml"
readonly KEEPSECRET_ICON_PATH="/usr/local/share/icons/hicolor/scalable/apps/org.kde.keepsecret.svg"
readonly KEEPSECRET_LOGGING_CATEGORIES_PATH="/usr/local/share/qlogging-categories6/keepsecret.categories"
readonly KEEPSECRET_TMP_ROOT_PREFIX="/tmp/labwc-keepsecret"
readonly KEEPSECRET_MANIFEST_DIR="/var/lib/labwc-session"
readonly KEEPSECRET_MANIFEST_PATH="${KEEPSECRET_MANIFEST_DIR}/keepsecret-install-manifest.txt"

keepsecret_work_root() {
  printf '%s\n' "$KEEPSECRET_TMP_ROOT_PREFIX"
}

validate_keepsecret_settings() {
  [[ "${GITHUB_KEEPSECRET_TAG:-}" =~ ^[A-Za-z0-9._-]+$ ]] || {
    die "GITHUB_KEEPSECRET_TAG must contain only alnum, dot, underscore, or dash, found '${GITHUB_KEEPSECRET_TAG:-}'"
  }
  [[ "${GITHUB_KEEPSECRET_URL:-}" =~ ^https://github\.com/[^/]+/[^/]+/releases/download/${GITHUB_KEEPSECRET_TAG}/[^/?#]+\.tar\.gz$ ]] || {
    die "GITHUB_KEEPSECRET_URL must be a GitHub release tarball for tag '${GITHUB_KEEPSECRET_TAG}', found '${GITHUB_KEEPSECRET_URL:-}'"
  }
  [[ "${GITHUB_KEEPSECRET_TARBALL_SHA:-}" =~ ^[0-9a-f]{64}$ ]] || {
    die "GITHUB_KEEPSECRET_TARBALL_SHA must be a 64 character lowercase hex sha256, found '${GITHUB_KEEPSECRET_TARBALL_SHA:-}'"
  }
  [[ "${GITHUB_KEEPSECRET_COMMIT_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || {
    die "GITHUB_KEEPSECRET_COMMIT_SHA must be a 40 character lowercase hex commit sha, found '${GITHUB_KEEPSECRET_COMMIT_SHA:-}'"
  }
}

install_keepsecret() {
  local work_root tarball_path extract_root

  validate_keepsecret_settings
  work_root="$(keepsecret_work_root)"
  tarball_path="${work_root}/keepsecret.tar.gz"
  extract_root="${work_root}/extract"

  [[ "$work_root" == /tmp/* ]] || die "keepsecret work root must stay under /tmp: $work_root"
  remove_keepsecret_install
  remove_if_present "$work_root"
  run_cmd install -d -m 0755 "$work_root"

  log_info "installing keepsecret ${GITHUB_KEEPSECRET_TAG} (${GITHUB_KEEPSECRET_COMMIT_SHA})"
  download_release_tarball "keepsecret" "$GITHUB_KEEPSECRET_URL" "$GITHUB_KEEPSECRET_TARBALL_SHA" "$tarball_path"
  extract_release_payload_tree "keepsecret" "$tarball_path" "usr/local" "$extract_root"
  install_release_payload_tree "$extract_root" "$KEEPSECRET_MANIFEST_PATH"
  assert_release_binary_dependencies "$KEEPSECRET_BIN_PATH" "keepsecret"
  if command -v update-desktop-database >/dev/null 2>&1; then
    run_cmd update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
  fi
  remove_if_present "$work_root"
}

remove_keepsecret_install() {
  remove_release_manifest_install "$KEEPSECRET_MANIFEST_PATH"
  remove_if_present "$KEEPSECRET_BIN_PATH"
  remove_if_present "$KEEPSECRET_DESKTOP_PATH"
  remove_if_present "$KEEPSECRET_APPDATA_PATH"
  remove_if_present "$KEEPSECRET_ICON_PATH"
  remove_if_present "$KEEPSECRET_LOGGING_CATEGORIES_PATH"
  remove_if_present "$(keepsecret_work_root)"
}
