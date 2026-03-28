#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

command -v gpg >/dev/null 2>&1 || exit 0
command -v gpgconf >/dev/null 2>&1 || exit 0
pinentry_bin="$(command -v pinentry-gtk-2 || true)"
[[ -n "$pinentry_bin" ]] || exit 0

export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
key_fpr="$(
  gpg --batch --list-secret-keys --with-colons 2>/dev/null | awk -F: '
    $1 == "sec" {want_fpr = 1; next}
    want_fpr && $1 == "fpr" {print $10; exit}
  '
)"
[[ -n "$key_fpr" ]] || exit 0

current_tty="$(tty 2>/dev/null || true)"
if [[ -n "${current_tty:-}" && "${current_tty}" != "not a tty" ]]; then
  export GPG_TTY="$current_tty"
fi

gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true

tmpdir="${XDG_RUNTIME_DIR:-/tmp}"
tmpfile="$(mktemp "${tmpdir%/}/debian-labwc-gpg-unlock.XXXXXX")"
cleanup() {
  rm -f -- "$tmpfile"
}
trap cleanup EXIT

pinentry_output="$(
  "$pinentry_bin" <<'EOF'
SETTITLE Debian Labwc GPG Unlock
SETDESC Enter the GPG password to unlock the KWallet encryption key for this session.
SETPROMPT GPG Password:
GETPIN
EOF
)"
passphrase="$(printf '%s\n' "$pinentry_output" | awk '/^D / {sub(/^D /, "", $0); print; exit}')"
[[ -n "$passphrase" ]] || exit 0

printf '%s\n' "debian-labwc-gpg-unlock" >"$tmpfile"
printf '%s\n' "$passphrase" | gpg --batch --quiet --local-user "$key_fpr" --pinentry-mode loopback --passphrase-fd 0 --detach-sign --output /dev/null "$tmpfile"
