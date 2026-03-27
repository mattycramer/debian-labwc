#!/usr/bin/env bash

readonly NWG_DOCK_AUTOSTART_MARKER_BEGIN="# >>> MANAGED BY debian-labwc nwg-dock >>>"
readonly NWG_DOCK_AUTOSTART_MARKER_END="# <<< MANAGED BY debian-labwc nwg-dock <<<"
readonly NWG_DOCK_BUILD_ROOT="/usr/local/src/nwg-dock"
readonly NWG_DOCK_SOURCE_DIR="$NWG_DOCK_BUILD_ROOT/source"
readonly NWG_DOCK_BUILD_DIR="$NWG_DOCK_BUILD_ROOT/build"
readonly NWG_DOCK_BIN_PATH="/usr/bin/nwg-dock"
readonly NWG_DOCK_DATA_PATH="/usr/share/nwg-dock"
readonly NWG_DOCK_WRAPPER_PATH="/usr/local/bin/debian-labwc-nwg-dock"

readonly NWG_DOCK_BUILD_PACKAGES=(
  ca-certificates
  curl
  golang-go
  pkg-config
  gcc
  libc6-dev
  libgtk-3-dev
  libgtk-layer-shell-dev
)

apt_yes_args() {
  if [[ "${ASSUME_YES:-1}" -eq 1 ]]; then
    printf '%s\n' "-y"
  fi
}

detect_target_user() {
  if [[ -n "${NWG_TARGET_USER:-}" ]] && id "$NWG_TARGET_USER" >/dev/null 2>&1; then
    :
  elif [[ -n "${LABWC_TARGET_USER:-}" ]] && id "$LABWC_TARGET_USER" >/dev/null 2>&1; then
    NWG_TARGET_USER="$LABWC_TARGET_USER"
  elif [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER:-}" != "root" ]] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
    NWG_TARGET_USER="$SUDO_USER"
  else
    NWG_TARGET_USER="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(false|nologin)$/ {print $1; exit}')"
  fi
  [[ -n "${NWG_TARGET_USER:-}" ]] || die "could not determine nwg-dock target user"
  NWG_TARGET_HOME="$(getent passwd "$NWG_TARGET_USER" | awk -F: '{print $6}')"
  [[ -n "${NWG_TARGET_HOME:-}" ]] || die "could not determine nwg-dock target home"
  NWG_TARGET_GROUP="$(id -gn "$NWG_TARGET_USER")"
  [[ -n "${NWG_TARGET_GROUP:-}" ]] || die "could not determine nwg-dock target group"
}

apt_update() {
  run_cmd env DEBIAN_FRONTEND=noninteractive apt update -o Acquire::Retries=3 -o Acquire::http::Timeout=20
}

install_nwg_dock_dependencies() {
  local -a apt_args=()
  mapfile -t apt_args < <(apt_yes_args)
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends "${apt_args[@]}" "${NWG_DOCK_BUILD_PACKAGES[@]}"
}

write_root_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"
  run_cmd install -D -m "$mode" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chmod "$mode" "$destination"
}

write_user_file() {
  local destination="$1"
  local mode="$2"
  local content="$3"
  run_cmd install -D -m "$mode" -o "$NWG_TARGET_USER" -g "$NWG_TARGET_USER" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$NWG_TARGET_USER:$NWG_TARGET_USER" "$destination"
  run_cmd chmod "$mode" "$destination"
}

prepare_nwg_download_path() {
  local path="$1"
  run_cmd runuser -u "$NWG_TARGET_USER" -- mkdir -p "$(dirname "$path")"
  run_cmd runuser -u "$NWG_TARGET_USER" -- rm -f -- "$path"
}

install_nwg_dock_from_source() {
  local archive_path
  archive_path="${NWG_DOCK_BUILD_ROOT}/nwg-dock.tar.gz"
  log_info "building nwg-dock from pinned source commit ${NWG_DOCK_COMMIT}"
  run_cmd install -d -m 0755 "$NWG_DOCK_BUILD_ROOT"
  run_cmd rm -rf -- "$NWG_DOCK_SOURCE_DIR" "$NWG_DOCK_BUILD_DIR"
  run_cmd install -d -m 0755 -o "$NWG_TARGET_USER" -g "$NWG_TARGET_GROUP" "$NWG_DOCK_SOURCE_DIR" "$NWG_DOCK_BUILD_DIR"
  prepare_nwg_download_path "$archive_path"
  run_cmd runuser -u "$NWG_TARGET_USER" -- env HOME="$NWG_TARGET_HOME" TMPDIR=/tmp curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 180 --silent --show-error -o "$archive_path" "$NWG_DOCK_SOURCE_URL"
  run_cmd tar -xzf "$archive_path" -C "$NWG_DOCK_SOURCE_DIR" --strip-components=1
  run_cmd rm -f -- "$archive_path"
  run_cmd chown -R "$NWG_TARGET_USER:$NWG_TARGET_GROUP" "$NWG_DOCK_SOURCE_DIR" "$NWG_DOCK_BUILD_DIR"
  run_cmd runuser -u "$NWG_TARGET_USER" -- env HOME="$NWG_TARGET_HOME" TMPDIR=/tmp bash -lc "cd '$NWG_DOCK_SOURCE_DIR' && GOCACHE='$NWG_DOCK_BUILD_DIR/gocache' GOPATH='$NWG_DOCK_BUILD_DIR/gopath' go mod download"
  run_cmd runuser -u "$NWG_TARGET_USER" -- env HOME="$NWG_TARGET_HOME" TMPDIR=/tmp bash -lc "cd '$NWG_DOCK_SOURCE_DIR' && GOCACHE='$NWG_DOCK_BUILD_DIR/gocache' GOPATH='$NWG_DOCK_BUILD_DIR/gopath' go build -v -o '$NWG_DOCK_BUILD_DIR/nwg-dock' ."
  run_cmd install -D -m 0755 "$NWG_DOCK_BUILD_DIR/nwg-dock" "$NWG_DOCK_BIN_PATH"
  run_cmd rm -rf -- "$NWG_DOCK_DATA_PATH"
  run_cmd install -d -m 0755 "$NWG_DOCK_DATA_PATH"
  run_cmd cp -a "$NWG_DOCK_SOURCE_DIR/images" "$NWG_DOCK_DATA_PATH/"
  run_cmd cp -a "$NWG_DOCK_SOURCE_DIR/config/." "$NWG_DOCK_DATA_PATH/"
}

resident_flags() {
  case "${NWG_DOCK_RESIDENT_MODE:-autohide}" in
    autohide) printf '%s\n' "-d" ;;
    resident) printf '%s\n' "-r" ;;
    none) printf '%s\n' "" ;;
    *) die "NWG_DOCK_RESIDENT_MODE must be autohide, resident, or none" ;;
  esac
}

yes_no_flag() {
  local value="$1"
  local flag="$2"
  case "$value" in
    yes) printf '%s\n' "$flag" ;;
    no) printf '%s\n' "" ;;
    *) die "invalid yes/no value '$value' for $flag" ;;
  esac
}

render_nwg_dock_wrapper() {
  local no_ws_flag resident_flag output_flag output_clause
  resident_flag="$(resident_flags)"
  no_ws_flag="$(yes_no_flag "${NWG_DOCK_NO_WORKSPACE_SWITCHER:-yes}" "-nows")"
  output_clause=""
  if [[ -n "${NWG_DOCK_OUTPUT:-}" ]]; then
    output_clause="-o ${NWG_DOCK_OUTPUT}"
  fi
  local wrapper
  wrapper="$(cat <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=\$'\\n\\t'

if [[ -z "\${SWAYSOCK:-}" ]]; then
  printf '[debian-labwc-nwg-dock] sway-compatible IPC is unavailable; upstream nwg-dock expects sway IPC and will not start under plain labwc.\\n' >&2
  exit 0
fi

exec /usr/bin/nwg-dock \\
  -p ${NWG_DOCK_POSITION} \\
  -l ${NWG_DOCK_LAYER} \\
  -i ${NWG_DOCK_ICON_SIZE} \\
  -w ${NWG_DOCK_WORKSPACES} \\
  -a ${NWG_DOCK_ALIGN} \\
  -mt ${NWG_DOCK_MARGIN_TOP} \\
  -mr ${NWG_DOCK_MARGIN_RIGHT} \\
  -mb ${NWG_DOCK_MARGIN_BOTTOM} \\
  -ml ${NWG_DOCK_MARGIN_LEFT} \\
  -hd ${NWG_DOCK_HOTSPOT_DELAY_MS} \\
  -c '${NWG_DOCK_LAUNCHER_CMD}' \\
  ${resident_flag} \\
  ${no_ws_flag} \\
  ${output_clause} \\
  "\$@"
EOF
)"
  write_root_file "$NWG_DOCK_WRAPPER_PATH" 0755 "$wrapper"
}

render_nwg_dock_style() {
  local style
  style="$(cat <<'EOF'
window {
  background: rgba(16, 20, 28, 0.92);
  border-radius: 14px;
  border: 1px solid rgba(115, 133, 156, 0.32);
}

#box {
  padding: 8px;
}

#active {
  border-bottom: solid 2px;
  border-color: rgba(109, 196, 237, 0.90);
}

button,
image {
  background: none;
  border-style: none;
  box-shadow: none;
  color: #eef2f7;
}

button {
  padding: 6px;
  margin-left: 4px;
  margin-right: 4px;
  font-size: 12px;
}

button:hover {
  background-color: rgba(109, 196, 237, 0.16);
  border-radius: 8px;
}

button:focus {
  box-shadow: none;
}
EOF
)"
  write_user_file "$NWG_TARGET_HOME/.config/nwg-dock/style.css" 0644 "$style"
}

render_nwg_dock_notes() {
  local notes
  notes="$(cat <<'EOF'
This module builds and installs upstream nwg-dock.
Upstream nwg-dock is sway-only in practice and expects SWAYSOCK-backed sway IPC at runtime.
The wrapper only launches when SWAYSOCK is present.
The Labwc wrapper intentionally skips launch when sway-compatible IPC is unavailable.
EOF
)"
  write_user_file "$NWG_TARGET_HOME/.config/nwg-dock/LABWC-COMPATIBILITY.txt" 0644 "$notes"
}

render_nwg_dock_autostart_fragment() {
  local fragment
  fragment="$(cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

command -v /usr/local/bin/debian-labwc-nwg-dock >/dev/null 2>&1 || exit 0
pgrep -x nwg-dock >/dev/null 2>&1 && exit 0
/usr/local/bin/debian-labwc-nwg-dock >/dev/null 2>&1 &
EOF
)"
  write_user_file "$NWG_TARGET_HOME/.config/labwc/autostart.d/60-nwg-dock.sh" 0755 "$fragment"
}

ensure_labwc_autostart_hook() {
  local autostart_path="$NWG_TARGET_HOME/.config/labwc/autostart"
  [[ -f "$autostart_path" ]] || return 0
  grep -F '.config/labwc/autostart.d' "$autostart_path" >/dev/null && return 0
  grep -F "$NWG_DOCK_AUTOSTART_MARKER_BEGIN" "$autostart_path" >/dev/null && return 0
  local hook
  hook="$(cat <<EOF

$NWG_DOCK_AUTOSTART_MARKER_BEGIN
autostart_dir="$NWG_TARGET_HOME/.config/labwc/autostart.d"
if [[ -d "\$autostart_dir" ]]; then
  while IFS= read -r -d '' autostart_fragment; do
    bash "\$autostart_fragment" >/dev/null 2>&1 || true
  done < <(find "\$autostart_dir" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)
fi
$NWG_DOCK_AUTOSTART_MARKER_END
EOF
)"
  printf '%s' "$hook" >>"$autostart_path"
  run_cmd chown "$NWG_TARGET_USER:$NWG_TARGET_USER" "$autostart_path"
}

render_nwg_dock_config() {
  run_cmd install -d -m 0755 -o "$NWG_TARGET_USER" -g "$NWG_TARGET_USER" \
    "$NWG_TARGET_HOME/.config" \
    "$NWG_TARGET_HOME/.config/nwg-dock" \
    "$NWG_TARGET_HOME/.config/labwc" \
    "$NWG_TARGET_HOME/.config/labwc/autostart.d"
  render_nwg_dock_wrapper
  render_nwg_dock_style
  render_nwg_dock_notes
  render_nwg_dock_autostart_fragment
  ensure_labwc_autostart_hook
  run_cmd chown -R "$NWG_TARGET_USER:$NWG_TARGET_USER" \
    "$NWG_TARGET_HOME/.config/nwg-dock" \
    "$NWG_TARGET_HOME/.config/labwc/autostart.d"
}

verify_nwg_dock_install() {
  require_file "$NWG_DOCK_BIN_PATH"
  require_dir "$NWG_DOCK_DATA_PATH"
  require_dir "$NWG_DOCK_DATA_PATH/images"
  require_file "$NWG_DOCK_DATA_PATH/style.css"
  require_file "$NWG_DOCK_WRAPPER_PATH"
  require_file "$NWG_TARGET_HOME/.config/nwg-dock/style.css"
  require_file "$NWG_TARGET_HOME/.config/nwg-dock/LABWC-COMPATIBILITY.txt"
  require_file "$NWG_TARGET_HOME/.config/labwc/autostart.d/60-nwg-dock.sh"
  grep -F 'sway-compatible IPC is unavailable' "$NWG_DOCK_WRAPPER_PATH" >/dev/null || die "wrapper missing Labwc compatibility guard"
  grep -F 'sway-only' "$NWG_TARGET_HOME/.config/nwg-dock/LABWC-COMPATIBILITY.txt" >/dev/null || die "compatibility note missing sway-only warning"
  [[ "$(stat -c '%U:%G' "$NWG_TARGET_HOME/.config/nwg-dock/style.css")" == "$NWG_TARGET_USER:$NWG_TARGET_USER" ]] || die "nwg-dock config ownership is wrong"
  log_info "verification completed"
}

remove_nwg_dock_install() {
  run_cmd rm -f -- "$NWG_DOCK_BIN_PATH" "$NWG_DOCK_WRAPPER_PATH"
  run_cmd rm -rf -- "$NWG_DOCK_DATA_PATH" "$NWG_DOCK_SOURCE_DIR" "$NWG_DOCK_BUILD_DIR"
  run_cmd rm -rf -- "$NWG_TARGET_HOME/.config/nwg-dock"
  run_cmd rm -f -- "$NWG_TARGET_HOME/.config/labwc/autostart.d/60-nwg-dock.sh"

  local autostart_path="$NWG_TARGET_HOME/.config/labwc/autostart"
  if [[ -f "$autostart_path" ]]; then
    sed -i "/$NWG_DOCK_AUTOSTART_MARKER_BEGIN/,/$NWG_DOCK_AUTOSTART_MARKER_END/d" "$autostart_path"
    run_cmd chown "$NWG_TARGET_USER:$NWG_TARGET_USER" "$autostart_path"
  fi
}
