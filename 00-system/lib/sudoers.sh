#!/usr/bin/env bash

readonly SYSTEM_SUDOERS_PATH="/etc/sudoers"
readonly SYSTEM_SUDOERS_D_PATH="/etc/sudoers.d"
readonly SYSTEM_SUDOERS_DROPIN_MODE="0440"

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

build_managed_sudoers_candidate() {
  local destination_path="$1"

  cat >"$destination_path" <<EOF
# Managed locally. Do not edit manually.
Defaults:${SYSTEM_TARGET_USER} env_reset
Defaults:${SYSTEM_TARGET_USER} use_pty
Defaults:${SYSTEM_TARGET_USER} !setenv
Defaults:${SYSTEM_TARGET_USER} secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults:${SYSTEM_TARGET_USER} passwd_tries=3
Defaults:${SYSTEM_TARGET_USER} timestamp_timeout=15
Defaults:${SYSTEM_TARGET_USER} verifypw=always
Defaults:${SYSTEM_TARGET_USER} listpw=always

Runas_Alias LOCAL_ADMIN_ROOT = root

Cmnd_Alias LOCAL_PKG_QUERY = \
    /usr/bin/apt-cache policy, \
    /usr/bin/apt-cache policy *, \
    /usr/bin/apt-cache search *, \
    /usr/bin/apt-cache show *, \
    /usr/bin/apt list, \
    /usr/bin/apt list *, \
    /usr/bin/dpkg -l, \
    /usr/bin/dpkg -l *, \
    /usr/bin/dpkg-query -l, \
    /usr/bin/dpkg-query -W, \
    /usr/bin/dpkg-query -W *
Cmnd_Alias LOCAL_PKG_MAINT = \
    /usr/bin/apt update, \
    /usr/bin/apt update *, \
    /usr/bin/apt upgrade, \
    /usr/bin/apt upgrade *, \
    /usr/bin/apt full-upgrade, \
    /usr/bin/apt full-upgrade *, \
    /usr/bin/apt autoremove, \
    /usr/bin/apt autoremove *, \
    /usr/bin/apt autoclean, \
    /usr/bin/apt clean, \
    /usr/bin/apt-get update, \
    /usr/bin/apt-get update *, \
    /usr/bin/apt-get upgrade, \
    /usr/bin/apt-get upgrade *, \
    /usr/bin/apt-get full-upgrade, \
    /usr/bin/apt-get full-upgrade *, \
    /usr/bin/apt-get dist-upgrade, \
    /usr/bin/apt-get dist-upgrade *, \
    /usr/bin/apt-get autoremove, \
    /usr/bin/apt-get autoremove *, \
    /usr/bin/apt-get autoclean, \
    /usr/bin/apt-get clean
Cmnd_Alias LOCAL_STORAGE_READ = \
    /usr/bin/findmnt, \
    /usr/bin/findmnt *, \
    /usr/bin/lsblk, \
    /usr/bin/lsblk *, \
    /usr/sbin/blkid, \
    /usr/sbin/blkid *
Cmnd_Alias LOCAL_DATA_DIRS = \
    /usr/bin/install -d /data/*, \
    /usr/bin/install -d * /data/*, \
    /usr/bin/mkdir -p /data/*, \
    /usr/bin/chown * /data/*, \
    /usr/bin/chmod * /data/*, \
    /usr/bin/find /data/*, \
    /usr/bin/stat /data/*, \
    /usr/bin/ls /data/*
Cmnd_Alias LOCAL_MOUNTS = \
    /usr/bin/mount /data/mnt/g-drive*, \
    /usr/bin/umount /data/mnt/g-drive*
Cmnd_Alias LOCAL_SERVICE_READ = \
    /usr/bin/systemctl status *, \
    /usr/bin/systemctl is-active *, \
    /usr/bin/systemctl is-enabled *, \
    /usr/bin/journalctl -u *, \
    /usr/bin/journalctl -xeu *, \
    /usr/bin/journalctl -n * -u *

${SYSTEM_TARGET_USER} ALL = (LOCAL_ADMIN_ROOT) NOPASSWD: \
    LOCAL_PKG_QUERY, \
    LOCAL_PKG_MAINT, \
    LOCAL_STORAGE_READ, \
    LOCAL_DATA_DIRS, \
    LOCAL_MOUNTS, \
    LOCAL_SERVICE_READ
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
    return 0
  fi

  run_cmd rm -f -- "$SYSTEM_SUDOERS_DROPIN_PATH"
  if ! "$SYSTEM_VISUDO_BIN" -cf "$SYSTEM_SUDOERS_PATH" >/dev/null; then
    die "live sudoers validation failed after removing $SYSTEM_SUDOERS_DROPIN_PATH"
  fi

  log_info "removed managed sudoers policy from $SYSTEM_SUDOERS_DROPIN_PATH"
}

verify_managed_sudoers() {
  local candidate_path actual_state

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

  "$SYSTEM_VISUDO_BIN" -cf "$SYSTEM_SUDOERS_PATH" >/dev/null || {
    die "sudoers validation failed for $SYSTEM_SUDOERS_PATH"
  }
}
