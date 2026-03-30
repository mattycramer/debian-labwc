#!/usr/bin/env bash

readonly SYSTEM_TORRENT_USER="torrent"
readonly SYSTEM_TORRENT_GROUP="torrent"
readonly SYSTEM_TORRENT_HOME="/nonexistent"

torrent_nologin_shell() {
  command -v nologin
}

ensure_system_group() {
  local group_name="$1"
  local gid

  if getent group "$group_name" >/dev/null 2>&1; then
    gid="$(getent group "$group_name" | awk -F: '{print $3}')"
    [[ "$gid" =~ ^[0-9]+$ ]] || die "could not parse GID for '$group_name'"
    ((gid < 1000)) || die "existing group '$group_name' is not a system group (gid=$gid)"
    return 0
  fi

  run_cmd groupadd --system "$group_name"
}

ensure_locked_system_user() {
  local user_name="$1"
  local group_name="$2"
  local home_path="$3"
  local expected_shell
  local uid gid home shell primary_group shadow_hash

  ensure_system_group "$group_name"
  expected_shell="$(readlink -f "$(torrent_nologin_shell)")"

  if id "$user_name" >/dev/null 2>&1; then
    uid="$(id -u "$user_name")"
    gid="$(id -g "$user_name")"
    home="$(getent passwd "$user_name" | awk -F: '{print $6}')"
    shell="$(getent passwd "$user_name" | awk -F: '{print $7}')"
    primary_group="$(id -gn "$user_name")"
    [[ "$uid" =~ ^[0-9]+$ ]] || die "could not parse UID for '$user_name'"
    [[ "$gid" =~ ^[0-9]+$ ]] || die "could not parse GID for '$user_name'"
    ((uid < 1000)) || die "existing user '$user_name' is not a system user (uid=$uid)"
    ((gid < 1000)) || die "existing user '$user_name' does not use a system group (gid=$gid)"
    [[ "$home" == "$home_path" ]] || die "existing user '$user_name' does not use home '$home_path'"
    [[ "$(readlink -f "$shell")" == "$expected_shell" ]] || die "existing user '$user_name' does not use the required nologin shell"
    [[ "$primary_group" == "$group_name" ]] || die "existing user '$user_name' does not have primary group '$group_name'"
  else
    run_cmd useradd \
      --system \
      --gid "$group_name" \
      --home-dir "$home_path" \
      --no-create-home \
      --shell "$(torrent_nologin_shell)" \
      "$user_name"
  fi

  shadow_hash="$(getent shadow "$user_name" | awk -F: '{print $2}')"
  case "$shadow_hash" in
    '!'*|'*')
      ;;
    *)
      run_cmd usermod --lock "$user_name"
      ;;
  esac
}

ensure_group_membership() {
  local user_name="$1"
  local group_name="$2"

  [[ "$user_name" != "root" ]] || return 0
  if id -nG "$user_name" | tr ' ' '\n' | grep -Fx "$group_name" >/dev/null 2>&1; then
    return 0
  fi

  run_cmd usermod -a -G "$group_name" "$user_name"
}

apply_system_account_policies() {
  ensure_locked_system_user "$SYSTEM_TORRENT_USER" "$SYSTEM_TORRENT_GROUP" "$SYSTEM_TORRENT_HOME"
  ensure_group_membership "$SYSTEM_TARGET_USER" "$SYSTEM_TORRENT_GROUP"
}

verify_system_account_policies() {
  local home shell expected_shell primary_group supplementary_groups shadow_hash

  getent group "$SYSTEM_TORRENT_GROUP" >/dev/null 2>&1 || die "missing group '$SYSTEM_TORRENT_GROUP'"
  id "$SYSTEM_TORRENT_USER" >/dev/null 2>&1 || die "missing user '$SYSTEM_TORRENT_USER'"

  home="$(getent passwd "$SYSTEM_TORRENT_USER" | awk -F: '{print $6}')"
  shell="$(getent passwd "$SYSTEM_TORRENT_USER" | awk -F: '{print $7}')"
  expected_shell="$(readlink -f "$(torrent_nologin_shell)")"
  primary_group="$(id -gn "$SYSTEM_TORRENT_USER")"
  supplementary_groups="$(id -nG "$SYSTEM_TORRENT_USER" | tr ' ' '\n' | grep -Fvx "$SYSTEM_TORRENT_GROUP" || true)"
  shadow_hash="$(getent shadow "$SYSTEM_TORRENT_USER" | awk -F: '{print $2}')"

  [[ "$home" == "$SYSTEM_TORRENT_HOME" ]] || die "torrent service account home is '$home', expected '$SYSTEM_TORRENT_HOME'"
  [[ "$(readlink -f "$shell")" == "$expected_shell" ]] || die "torrent service account shell is '$shell', expected nologin"
  [[ "$primary_group" == "$SYSTEM_TORRENT_GROUP" ]] || die "torrent service account primary group is '$primary_group', expected '$SYSTEM_TORRENT_GROUP'"
  [[ -z "$supplementary_groups" ]] || die "torrent service account has unexpected supplementary groups: $supplementary_groups"
  case "$shadow_hash" in
    '!'*|'*')
      ;;
    *)
      die "torrent service account password is not locked"
      ;;
  esac

  if [[ "$SYSTEM_TARGET_USER" != "root" ]]; then
    id -nG "$SYSTEM_TARGET_USER" | tr ' ' '\n' | grep -Fx "$SYSTEM_TORRENT_GROUP" >/dev/null 2>&1 || {
      die "invoking user '$SYSTEM_TARGET_USER' is not a member of '$SYSTEM_TORRENT_GROUP'"
    }
  fi
}
