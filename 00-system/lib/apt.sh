#!/usr/bin/env bash

readonly SID_SOURCE_PATH="/etc/apt/sources.list.d/sid.sources"
readonly BACKPORTS_SOURCE_PATH="/etc/apt/sources.list.d/trixie-backports.sources"
readonly SID_PREFERENCES_PATH="/etc/apt/preferences.d/sid"
readonly DEBIAN_ARCHIVE_KEYRING_PATH="/usr/share/keyrings/debian-archive-keyring.gpg"
readonly BACKPORTS_SUITE="trixie-backports"

managed_sid_source_content() {
  cat <<'EOF'
Types: deb deb-src
URIs: https://deb.debian.org/debian
Suites: sid
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
}

managed_backports_source_content() {
  cat <<EOF
Types: deb deb-src
URIs: https://deb.debian.org/debian
Suites: ${BACKPORTS_SUITE}
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
}

managed_sid_preferences_content() {
  cat <<'EOF'
Package: *
Pin: release n=sid
Pin-Priority: 100
EOF
}

apply_managed_sid_repository() {
  [[ -f "$DEBIAN_ARCHIVE_KEYRING_PATH" ]] || die "missing Debian archive keyring: $DEBIAN_ARCHIVE_KEYRING_PATH"
  run_cmd install -D -m 0644 /dev/null "$SID_SOURCE_PATH"
  managed_sid_source_content >"$SID_SOURCE_PATH"
  run_cmd install -D -m 0644 /dev/null "$BACKPORTS_SOURCE_PATH"
  managed_backports_source_content >"$BACKPORTS_SOURCE_PATH"
  run_cmd install -D -m 0644 /dev/null "$SID_PREFERENCES_PATH"
  managed_sid_preferences_content >"$SID_PREFERENCES_PATH"
}

remove_managed_sid_repository() {
  run_cmd rm -f -- "$SID_SOURCE_PATH" "$BACKPORTS_SOURCE_PATH" "$SID_PREFERENCES_PATH"
}
