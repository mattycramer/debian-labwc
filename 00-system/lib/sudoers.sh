#!/usr/bin/env bash

readonly SYSTEM_SUDOERS_PATH="/etc/sudoers"
readonly SYSTEM_SUDOERS_D_PATH="/etc/sudoers.d"
readonly SYSTEM_SUDOERS_DROPIN_MODE="0440"
readonly SYSTEM_SUDOERS_HELPER_DIR="/usr/local/libexec/labwc-system"
readonly SYSTEM_STATUS_MANAGED_MOUNTS_HELPER="${SYSTEM_SUDOERS_HELPER_DIR}/status-managed-mounts"
readonly SYSTEM_JOURNAL_MANAGED_MOUNTS_HELPER="${SYSTEM_SUDOERS_HELPER_DIR}/journal-managed-mounts"
readonly SYSTEM_STATUS_QBITTORRENT_HELPER="${SYSTEM_SUDOERS_HELPER_DIR}/status-qbittorrent"
readonly SYSTEM_JOURNAL_QBITTORRENT_HELPER="${SYSTEM_SUDOERS_HELPER_DIR}/journal-qbittorrent"

resolve_visudo_bin() {
  if [[ -n "${SYSTEM_VISUDO_BIN:-}" ]] && [[ -x "${SYSTEM_VISUDO_BIN:-}" ]]; then
    return 0
  fi

  local candidate
  for candidate in /usr/sbin/visudo /usr/bin/visudo; do
    if [[ -x "$candidate" ]]; then
      SYSTEM_VISUDO_BIN="$candidate"
      return 0
    fi
  done

  candidate="$(command -v visudo 2>/dev/null || true)"
  if [[ -n "$candidate" ]] && [[ -x "$candidate" ]]; then
    SYSTEM_VISUDO_BIN="$candidate"
    return 0
  fi

  die "could not locate visudo"
}

require_supported_sudoers_user() {
  [[ "$SYSTEM_TARGET_USER" =~ ^[A-Za-z0-9_.-]+[$]?$ ]] || {
    die "unsupported invoking user for sudoers policy: $SYSTEM_TARGET_USER"
  }
}

sanitize_sudoers_fragment() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9_-]/_/g'
}

resolve_sudoers_dropin_path() {
  local safe_user

  safe_user="$(sanitize_sudoers_fragment "$SYSTEM_TARGET_USER")"
  SYSTEM_SUDOERS_DROPIN_NAME="90-${safe_user}"
  SYSTEM_SUDOERS_DROPIN_PATH="$SYSTEM_SUDOERS_D_PATH/$SYSTEM_SUDOERS_DROPIN_NAME"
}

sudoers_includes_dropin_dir() {
  awk -v include_path="$SYSTEM_SUDOERS_D_PATH" '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ /^[@#]includedir[[:space:]]+/) {
        keyword = line
        sub(/[[:space:]].*$/, "", keyword)
        sub(/^[@#]includedir[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        gsub(/\/+$/, "", line)
        if (line == include_path) {
          found = 1
          exit 0
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$SYSTEM_SUDOERS_PATH"
}

ensure_sudoers_dropin_dir() {
  run_cmd install -d -m 0755 -o root -g root "$SYSTEM_SUDOERS_D_PATH"
}

write_root_helper_script() {
  local destination_path="$1"
  local content="$2"

  run_cmd install -d -m 0755 -o root -g root "$SYSTEM_SUDOERS_HELPER_DIR"
  run_cmd install -m 0755 -o root -g root /dev/null "$destination_path"
  printf '%s\n' "$content" >"$destination_path"
  run_cmd chown root:root "$destination_path"
  run_cmd chmod 0755 "$destination_path"
}

render_status_managed_mounts_helper() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

(($# == 0)) || {
  printf 'this helper does not accept arguments\n' >&2
  exit 64
}

manifest="/var/lib/local-mounts/managed-units.list"
declare -a units=()

if [[ -f "$manifest" ]]; then
  while IFS='|' read -r unit_name unit_state hook; do
    [[ -n "$unit_name" ]] || continue
    units+=("$unit_name")
  done <"$manifest"
fi

((${#units[@]} > 0)) || {
  printf 'no managed mount units are installed\n'
  exit 0
}

exec /usr/bin/systemctl --no-pager --full status "${units[@]}"
EOF
}

render_journal_managed_mounts_helper() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

(($# == 0)) || {
  printf 'this helper does not accept arguments\n' >&2
  exit 64
}

manifest="/var/lib/local-mounts/managed-units.list"
declare -a units=()
declare -a args=()

if [[ -f "$manifest" ]]; then
  while IFS='|' read -r unit_name unit_state hook; do
    [[ -n "$unit_name" ]] || continue
    units+=("$unit_name")
  done <"$manifest"
fi

((${#units[@]} > 0)) || {
  printf 'no managed mount units are installed\n'
  exit 0
}

for unit_name in "${units[@]}"; do
  args+=("-u" "$unit_name")
done

exec /usr/bin/journalctl --no-pager --no-hostname -n 200 "${args[@]}"
EOF
}

render_status_qbittorrent_helper() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

(($# == 0)) || {
  printf 'this helper does not accept arguments\n' >&2
  exit 64
}

exec /usr/bin/systemctl --no-pager --full status qbittorrent-nox.service
EOF
}

render_journal_qbittorrent_helper() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

(($# == 0)) || {
  printf 'this helper does not accept arguments\n' >&2
  exit 64
}

exec /usr/bin/journalctl --no-pager --no-hostname -n 200 -u qbittorrent-nox.service
EOF
}

install_managed_sudoers_helpers() {
  write_root_helper_script "$SYSTEM_STATUS_MANAGED_MOUNTS_HELPER" "$(render_status_managed_mounts_helper)"
  write_root_helper_script "$SYSTEM_JOURNAL_MANAGED_MOUNTS_HELPER" "$(render_journal_managed_mounts_helper)"
  write_root_helper_script "$SYSTEM_STATUS_QBITTORRENT_HELPER" "$(render_status_qbittorrent_helper)"
  write_root_helper_script "$SYSTEM_JOURNAL_QBITTORRENT_HELPER" "$(render_journal_qbittorrent_helper)"
}

build_managed_sudoers_candidate() {
  local destination_path="$1"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
Defaults:${SYSTEM_TARGET_USER} env_reset
Defaults:${SYSTEM_TARGET_USER} use_pty
Defaults:${SYSTEM_TARGET_USER} !setenv
Defaults:${SYSTEM_TARGET_USER} secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults:${SYSTEM_TARGET_USER} passwd_tries=3
Defaults:${SYSTEM_TARGET_USER} timestamp_timeout=5
Defaults:${SYSTEM_TARGET_USER} verifypw=always
Defaults:${SYSTEM_TARGET_USER} listpw=always

Runas_Alias LOCAL_ADMIN_ROOT = root

Cmnd_Alias LOCAL_STATUS_READ = \
    ${SYSTEM_STATUS_MANAGED_MOUNTS_HELPER}, \
    ${SYSTEM_JOURNAL_MANAGED_MOUNTS_HELPER}, \
    ${SYSTEM_STATUS_QBITTORRENT_HELPER}, \
    ${SYSTEM_JOURNAL_QBITTORRENT_HELPER}

${SYSTEM_TARGET_USER} ALL = (LOCAL_ADMIN_ROOT) NOPASSWD: \
    LOCAL_STATUS_READ
${SYSTEM_TARGET_USER} ALL = (ALL:ALL) PASSWD: ALL
EOF
}

build_sudoers_validation_sandbox() {
  local candidate_path="$1"
  local sandbox_root="$2"
  local sandbox_sudoers="$3"
  local sandbox_dropins="$4"

  run_cmd install -d -m 0700 -o root -g root "$sandbox_root"
  run_cmd install -d -m 0755 -o root -g root "$sandbox_dropins"
  run_cmd cp -a -- "$SYSTEM_SUDOERS_PATH" "$sandbox_sudoers"
  if [[ -d "$SYSTEM_SUDOERS_D_PATH" ]]; then
    run_cmd cp -a -- "$SYSTEM_SUDOERS_D_PATH/." "$sandbox_dropins/"
  fi
  run_cmd install -m "$SYSTEM_SUDOERS_DROPIN_MODE" -o root -g root \
    "$candidate_path" "$sandbox_dropins/$SYSTEM_SUDOERS_DROPIN_NAME"

  awk -v include_path="$SYSTEM_SUDOERS_D_PATH" -v sandbox_path="$sandbox_dropins" '
    {
      line = $0
      trimmed = line
      sub(/^[[:space:]]+/, "", trimmed)
      if (trimmed ~ /^[@#]includedir[[:space:]]+/) {
        keyword = trimmed
        sub(/[[:space:]].*$/, "", keyword)
        sub(/^[@#]includedir[[:space:]]+/, "", trimmed)
        sub(/[[:space:]]+$/, "", trimmed)
        gsub(/\/+$/, "", trimmed)
        if (trimmed == include_path) {
          match($0, /^[[:space:]]*/)
          indent = substr($0, RSTART, RLENGTH)
          print indent keyword " " sandbox_path
          next
        }
      }
      print
    }
  ' "$sandbox_sudoers" >"${sandbox_sudoers}.tmp"
  run_cmd mv -- "${sandbox_sudoers}.tmp" "$sandbox_sudoers"
}

validate_sudoers_candidate() {
  local candidate_path="$1"
  local sandbox_root sandbox_sudoers sandbox_dropins

  sandbox_root="$(mktemp -d)"
  sandbox_sudoers="$sandbox_root/sudoers"
  sandbox_dropins="$sandbox_root/sudoers.d"

  build_sudoers_validation_sandbox \
    "$candidate_path" \
    "$sandbox_root" \
    "$sandbox_sudoers" \
    "$sandbox_dropins"

  if ! "$SYSTEM_VISUDO_BIN" -cf "$sandbox_sudoers" >/dev/null; then
    rm -rf -- "$sandbox_root"
    die "generated sudoers policy failed validation"
  fi

  rm -rf -- "$sandbox_root"
}

validate_managed_sudoers_policy() {
  local candidate_path

  candidate_path="$(mktemp)"
  build_managed_sudoers_candidate "$candidate_path"
  validate_sudoers_candidate "$candidate_path"
  rm -f -- "$candidate_path"
}

apply_managed_sudoers() {
  local candidate_path

  ensure_sudoers_dropin_dir
  install_managed_sudoers_helpers
  candidate_path="$(mktemp)"
  build_managed_sudoers_candidate "$candidate_path"
  validate_sudoers_candidate "$candidate_path"

  if [[ -f "$SYSTEM_SUDOERS_DROPIN_PATH" ]] && cmp -s "$candidate_path" "$SYSTEM_SUDOERS_DROPIN_PATH"; then
    log_info "$SYSTEM_SUDOERS_DROPIN_PATH is already up to date"
    rm -f -- "$candidate_path"
    return 0
  fi

  run_cmd install -m "$SYSTEM_SUDOERS_DROPIN_MODE" -o root -g root \
    "$candidate_path" "$SYSTEM_SUDOERS_DROPIN_PATH"
  if ! "$SYSTEM_VISUDO_BIN" -cf "$SYSTEM_SUDOERS_PATH" >/dev/null; then
    rm -f -- "$candidate_path"
    die "live sudoers validation failed after installing $SYSTEM_SUDOERS_DROPIN_PATH"
  fi

  rm -f -- "$candidate_path"
  log_info "updated $SYSTEM_SUDOERS_DROPIN_PATH"
}

remove_managed_sudoers() {
  if [[ ! -e "$SYSTEM_SUDOERS_DROPIN_PATH" ]]; then
    log_info "no managed sudoers policy present"
  else
    run_cmd rm -f -- "$SYSTEM_SUDOERS_DROPIN_PATH"
    if ! "$SYSTEM_VISUDO_BIN" -cf "$SYSTEM_SUDOERS_PATH" >/dev/null; then
      die "live sudoers validation failed after removing $SYSTEM_SUDOERS_DROPIN_PATH"
    fi

    log_info "removed managed sudoers policy from $SYSTEM_SUDOERS_DROPIN_PATH"
  fi

  run_cmd rm -f -- \
    "$SYSTEM_STATUS_MANAGED_MOUNTS_HELPER" \
    "$SYSTEM_JOURNAL_MANAGED_MOUNTS_HELPER" \
    "$SYSTEM_STATUS_QBITTORRENT_HELPER" \
    "$SYSTEM_JOURNAL_QBITTORRENT_HELPER"

  if [[ -d "$SYSTEM_SUDOERS_HELPER_DIR" ]] && [[ -z "$(find "$SYSTEM_SUDOERS_HELPER_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    run_cmd rmdir -- "$SYSTEM_SUDOERS_HELPER_DIR"
  fi
}

verify_managed_sudoers() {
  local candidate_path actual_state helper_path

  require_file "$SYSTEM_SUDOERS_DROPIN_PATH"
  candidate_path="$(mktemp)"
  build_managed_sudoers_candidate "$candidate_path"
  cmp -s "$candidate_path" "$SYSTEM_SUDOERS_DROPIN_PATH" || {
    rm -f -- "$candidate_path"
    die "$SYSTEM_SUDOERS_DROPIN_PATH does not match the generated sudoers state"
  }
  rm -f -- "$candidate_path"

  actual_state="$(stat -c '%U:%G:%a' "$SYSTEM_SUDOERS_DROPIN_PATH")"
  [[ "$actual_state" == "root:root:${SYSTEM_SUDOERS_DROPIN_MODE#0}" ]] || {
    die "unexpected sudoers drop-in state for $SYSTEM_SUDOERS_DROPIN_PATH: $actual_state"
  }

  for helper_path in \
    "$SYSTEM_STATUS_MANAGED_MOUNTS_HELPER" \
    "$SYSTEM_JOURNAL_MANAGED_MOUNTS_HELPER" \
    "$SYSTEM_STATUS_QBITTORRENT_HELPER" \
    "$SYSTEM_JOURNAL_QBITTORRENT_HELPER"; do
    require_file "$helper_path"
    actual_state="$(stat -c '%U:%G:%a' "$helper_path")"
    [[ "$actual_state" == "root:root:755" ]] || {
      die "unexpected helper state for $helper_path: $actual_state"
    }
  done

  "$SYSTEM_VISUDO_BIN" -cf "$SYSTEM_SUDOERS_PATH" >/dev/null || {
    die "sudoers validation failed for $SYSTEM_SUDOERS_PATH"
  }
}
