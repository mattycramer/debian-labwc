#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

command -v secret-tool >/dev/null 2>&1 || exit 0

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/debian-labwc"
seed_path="${state_dir}/kwallet-session-gpg-passphrase.seed"
fingerprint_path="${state_dir}/kwallet-session-gpg.fpr"

[[ -r "$seed_path" ]] || exit 0

passphrase="$(<"$seed_path")"
[[ -n "$passphrase" ]] || {
  rm -f -- "$seed_path"
  exit 0
}

fingerprint="unknown"
if [[ -r "$fingerprint_path" ]]; then
  fingerprint="$(tr -d '\n' <"$fingerprint_path")"
  [[ -n "$fingerprint" ]] || fingerprint="unknown"
fi

attempt=1
while (( attempt <= 5 )); do
  secret-tool clear service debian-labwc kind kwallet-session-gpg-passphrase user "$USER" >/dev/null 2>&1 || true
  if printf '%s' "$passphrase" | secret-tool store \
    --label="Debian Labwc KWallet Session GPG Passphrase" \
    service debian-labwc \
    kind kwallet-session-gpg-passphrase \
    user "$USER" \
    gpg_fingerprint "$fingerprint"; then
    rm -f -- "$seed_path"
    exit 0
  fi
  sleep 1
  attempt=$((attempt + 1))
done
