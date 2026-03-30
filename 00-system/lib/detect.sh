#!/usr/bin/env bash

detect_target_user() {
  local candidate=""
  if [[ -n "${SYSTEM_TARGET_USER:-}" ]] && id "$SYSTEM_TARGET_USER" >/dev/null 2>&1; then
    candidate="$SYSTEM_TARGET_USER"
  elif [[ -n "${SUDO_USER:-}" ]] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
    candidate="$SUDO_USER"
  else
    candidate="$(id -un)"
  fi
  [[ -n "$candidate" ]] || die "could not determine invoking user"

  SYSTEM_TARGET_USER="$candidate"
  SYSTEM_TARGET_UID="$(id -u "$candidate")"
  SYSTEM_TARGET_GROUP="$(id -gn "$candidate")"
  SYSTEM_TARGET_HOME="$(getent passwd "$candidate" | awk -F: '{print $6}')"

  [[ "$SYSTEM_TARGET_UID" != "0" ]] || die "refusing to target root; run 'make <target>' as a non-root user"
  [[ -n "${SYSTEM_TARGET_UID:-}" ]] || die "could not determine UID for '$candidate'"
  [[ -n "${SYSTEM_TARGET_GROUP:-}" ]] || die "could not determine primary group for '$candidate'"
  [[ -n "${SYSTEM_TARGET_HOME:-}" ]] || die "could not determine home for '$candidate'"
  [[ "$SYSTEM_TARGET_HOME" == /* ]] || die "home path must be absolute: $SYSTEM_TARGET_HOME"
}

print_resolved_config() {
  local payload_state="no"
  if mount_config_has_entries; then
    payload_state="yes"
  fi

  printf '%s\n' \
    "SYSTEM_TARGET_USER=\"$SYSTEM_TARGET_USER\"" \
    "SYSTEM_TARGET_UID=\"$SYSTEM_TARGET_UID\"" \
    "SYSTEM_TARGET_GROUP=\"$SYSTEM_TARGET_GROUP\"" \
    "SYSTEM_TARGET_HOME=\"$SYSTEM_TARGET_HOME\"" \
    "SYSTEM_SUDOERS_DROPIN_PATH=\"${SYSTEM_SUDOERS_DROPIN_PATH:-}\"" \
    "SYSTEM_MOUNTS_CONFIG_FILE=\"$MOUNTS_CONFIG_FILE\"" \
    "SYSTEM_MOUNTS_STATE_FILE=\"$SYSTEM_MOUNT_STATE_FILE\"" \
    "SYSTEM_MOUNTS_CONFIG_HAS_CONTENT=\"$payload_state\""
}
