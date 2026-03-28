#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

command -v gpg >/dev/null 2>&1 || {
  printf '%s\n' "gpg is required to generate a KWallet GPG key" >&2
  exit 1
}

export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
install -d -m 0700 "$GNUPGHOME"
chmod 0700 "$GNUPGHOME"

has_encryption_secret_key() {
  gpg --batch --list-secret-keys --with-colons 2>/dev/null | awk -F: '
    ($1 == "sec" || $1 == "ssb") && (index($12, "e") > 0 || index($12, "E") > 0) {
      found = 1
    }
    END {
      exit found ? 0 : 1
    }
  '
}

resolve_key_realname() {
  local gecos_name=""
  if [[ -n "${LABWC_GPG_KEY_REALNAME:-}" ]]; then
    printf '%s\n' "$LABWC_GPG_KEY_REALNAME"
    return 0
  fi
  if command -v getent >/dev/null 2>&1; then
    gecos_name="$(getent passwd "${LABWC_TARGET_USER:-$USER}" | awk -F: '{print $5}' | cut -d, -f1)"
  fi
  if [[ -n "$gecos_name" ]]; then
    printf '%s\n' "$gecos_name"
    return 0
  fi
  printf '%s\n' "${LABWC_TARGET_USER:-$USER}"
}

resolve_key_email() {
  if [[ -n "${LABWC_GPG_KEY_EMAIL:-}" ]]; then
    printf '%s\n' "$LABWC_GPG_KEY_EMAIL"
    return 0
  fi
  printf '%s\n' ""
}

main() {
  local key_uid key_realname key_email key_expire key_passphrase
  has_encryption_secret_key && exit 0
  key_realname="$(resolve_key_realname)"
  key_email="$(resolve_key_email)"
  key_expire="${LABWC_GPG_KEY_EXPIRE:-2y}"
  key_passphrase="${KWALLET_SESSION_GPG_PASSWD:-}"
  unset KWALLET_SESSION_GPG_PASSWD
  [[ -n "$key_passphrase" ]] || {
    printf '%s\n' "KWALLET_SESSION_GPG_PASSWD is required to generate a new KWallet GPG key" >&2
    exit 1
  }
  if [[ -n "$key_email" ]]; then
    key_uid="${key_realname} <${key_email}>"
  else
    key_uid="${key_realname}"
  fi
  printf '%s\n' "$key_passphrase" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 --quick-generate-key "$key_uid" default default "$key_expire"
}

main "$@"
