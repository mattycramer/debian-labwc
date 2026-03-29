#!/usr/bin/env bash

detect_target_user() {
  local candidate=""
  if [[ -n "${SYSTEM_TARGET_USER:-}" ]] && id "$SYSTEM_TARGET_USER" >/dev/null 2>&1; then
    candidate="$SYSTEM_TARGET_USER"
  elif [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER:-}" != "root" ]] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
    candidate="$SUDO_USER"
  else
    candidate="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(false|nologin)$/ {print $1; exit}')"
  fi
  [[ -n "$candidate" ]] || die "could not determine invoking user"

  SYSTEM_TARGET_USER="$candidate"
  SYSTEM_TARGET_GROUP="$(id -gn "$candidate")"
  SYSTEM_TARGET_HOME="$(getent passwd "$candidate" | awk -F: '{print $6}')"

  [[ -n "${SYSTEM_TARGET_GROUP:-}" ]] || die "could not determine primary group for '$candidate'"
  [[ -n "${SYSTEM_TARGET_HOME:-}" ]] || die "could not determine home for '$candidate'"
  [[ "$SYSTEM_TARGET_HOME" == /* ]] || die "home path must be absolute: $SYSTEM_TARGET_HOME"
}

print_resolved_config() {
  local payload_state="no"
  if fstab_payload_has_entries; then
    payload_state="yes"
  fi

  printf '%s\n' \
    "SYSTEM_TARGET_USER=\"$SYSTEM_TARGET_USER\"" \
    "SYSTEM_TARGET_GROUP=\"$SYSTEM_TARGET_GROUP\"" \
    "SYSTEM_TARGET_HOME=\"$SYSTEM_TARGET_HOME\"" \
    "SYSTEM_FSTAB_PATH=\"$SYSTEM_FSTAB_PATH\"" \
    "SYSTEM_FSTAB_ENV_FILE=\"$FSTAB_ENV_FILE\"" \
    "SYSTEM_FSTAB_PAYLOAD_HAS_CONTENT=\"$payload_state\""
}
