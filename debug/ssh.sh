#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

export LC_ALL=C
export TZ=UTC
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ENV_FILE="$SCRIPT_DIR/.env"
readonly SSHD_CONFIG_PATH="/etc/ssh/sshd_config"
readonly SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
readonly SSHD_DROPIN_PATH="${SSHD_DROPIN_DIR}/90-debian-labwc-publickey.conf"

PHASE="all"
TARGET_USER=""
TARGET_UID=""
TARGET_GROUP=""
TARGET_HOME=""
TARGET_SSH_DIR=""
AUTHORIZED_KEYS_PATH=""
SSH_PUBLIC_KEY=""

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log_info() {
  printf '[%s] INFO: %s\n' "$(timestamp)" "$*"
}

log_warn() {
  printf '[%s] WARN: %s\n' "$(timestamp)" "$*" >&2
}

log_error() {
  printf '[%s] ERROR: %s\n' "$(timestamp)" "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./ssh.sh [--phase doctor|install|verify|all]
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --phase)
        [[ $# -ge 2 ]] || die "missing value for --phase"
        PHASE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}

detect_target_user() {
  local candidate=""

  if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER:-}" != "root" ]] && id "${SUDO_USER:-}" >/dev/null 2>&1; then
    candidate="$SUDO_USER"
  else
    candidate="$(id -un)"
  fi

  [[ -n "$candidate" ]] || die "could not determine target user"

  TARGET_USER="$candidate"
  TARGET_UID="$(id -u "$TARGET_USER")"
  TARGET_GROUP="$(id -gn "$TARGET_USER")"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | awk -F: '{print $6}')"

  [[ "$TARGET_UID" != "0" ]] || die "refusing to target root; run this as a normal user"
  [[ -n "$TARGET_HOME" ]] || die "could not determine home for '$TARGET_USER'"
  [[ "$TARGET_HOME" == /* ]] || die "home path must be absolute: $TARGET_HOME"

  TARGET_SSH_DIR="${TARGET_HOME}/.ssh"
  AUTHORIZED_KEYS_PATH="${TARGET_SSH_DIR}/authorized_keys"

  [[ "$TARGET_USER" =~ ^[A-Za-z0-9_.-]+[$]?$ ]] || {
    die "unsupported target user for sshd policy: $TARGET_USER"
  }
}

read_env_value() {
  local key="$1"
  local line=""
  local value=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
      ''|\#*)
        continue
        ;;
      "${key}"=*)
        value="${line#*=}"
        if [[ "$value" == \"*\" && "$value" == *\" && ${#value} -ge 2 ]]; then
          value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && "$value" == *\' && ${#value} -ge 2 ]]; then
          value="${value:1:${#value}-2}"
        fi
        printf '%s' "$value"
        return 0
        ;;
    esac
  done <"$ENV_FILE"

  return 1
}

load_env_file() {
  require_file "$ENV_FILE"
  SSH_PUBLIC_KEY="$(read_env_value "SSH_PUBLIC_KEY")" || {
    die "missing SSH_PUBLIC_KEY in $ENV_FILE"
  }
}

validate_public_key() {
  [[ -n "$SSH_PUBLIC_KEY" ]] || die "SSH_PUBLIC_KEY must not be empty"
  [[ "$SSH_PUBLIC_KEY" != *$'\n'* ]] || die "SSH_PUBLIC_KEY must be a single line"
  [[ "$SSH_PUBLIC_KEY" != *$'\r'* ]] || die "SSH_PUBLIC_KEY must not contain carriage returns"
  [[ "$SSH_PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ecdsa-sha2-nistp256@openssh\.com|sk-ssh-ed25519@openssh\.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]][^[:cntrl:]]+)?$ ]] || {
    die "SSH_PUBLIC_KEY is not a supported single-line OpenSSH public key"
  }
}

require_sudo_access() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi

  require_command sudo
  sudo -v || die "sudo authentication failed"
}

sudo_run() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

package_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -Fxq 'install ok installed'
}

ensure_not_symlink() {
  local path="$1"

  if [[ -L "$path" ]]; then
    die "refusing to manage symlink path: $path"
  fi
}

ensure_openssh_server() {
  if package_installed "openssh-server"; then
    log_info "openssh-server is already installed"
    return 0
  fi

  require_sudo_access
  log_info "installing openssh-server"
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
}

sshd_config_includes_dropins() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*Include[[:space:]]+\/etc\/ssh\/sshd_config\.d\/\*\.conf([[:space:]]+.*)?$/ {
      found = 1
      exit 0
    }
    END { exit(found ? 0 : 1) }
  ' "$SSHD_CONFIG_PATH"
}

ensure_sshd_include() {
  local current_config=""
  local candidate_config=""

  require_file "$SSHD_CONFIG_PATH"
  if sshd_config_includes_dropins; then
    log_info "sshd_config already includes ${SSHD_DROPIN_DIR}"
    return 0
  fi

  require_sudo_access
  current_config="$(mktemp)"
  candidate_config="$(mktemp)"
  sudo_run cat "$SSHD_CONFIG_PATH" >"$current_config"
  {
    printf '%s\n' '# Managed by debug/ssh.sh to enable sshd drop-in configuration.'
    printf '%s\n' 'Include /etc/ssh/sshd_config.d/*.conf'
    cat "$current_config"
  } >"$candidate_config"

  log_info "adding sshd drop-in include to $SSHD_CONFIG_PATH"
  sudo_run install -m 0644 -o root -g root "$candidate_config" "$SSHD_CONFIG_PATH"

  rm -f -- "$current_config" "$candidate_config"
}

render_sshd_dropin() {
  cat <<EOF
# Managed by debug/ssh.sh. Do not edit manually.
AllowUsers ${TARGET_USER}
AuthenticationMethods publickey
KbdInteractiveAuthentication no
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
EOF
}

apply_sshd_dropin() {
  local candidate_path=""

  candidate_path="$(mktemp)"
  render_sshd_dropin >"$candidate_path"

  require_sudo_access
  sudo_run install -d -m 0755 -o root -g root "$SSHD_DROPIN_DIR"
  if sudo_run test -f "$SSHD_DROPIN_PATH" && sudo_run cmp -s "$candidate_path" "$SSHD_DROPIN_PATH"; then
    log_info "$SSHD_DROPIN_PATH already matches the managed configuration"
    rm -f -- "$candidate_path"
    return 0
  fi

  log_info "installing managed sshd drop-in at $SSHD_DROPIN_PATH"
  sudo_run install -m 0644 -o root -g root "$candidate_path" "$SSHD_DROPIN_PATH"
  rm -f -- "$candidate_path"
}

ensure_host_keys() {
  require_sudo_access
  log_info "ensuring SSH host keys exist"
  sudo_run ssh-keygen -A
}

build_authorized_keys_candidate() {
  local candidate_path="$1"
  local newline_count=""

  : >"$candidate_path"
  if [[ -f "$AUTHORIZED_KEYS_PATH" ]]; then
    cat -- "$AUTHORIZED_KEYS_PATH" >"$candidate_path"
  fi

  if grep -Fqx -- "$SSH_PUBLIC_KEY" "$candidate_path"; then
    return 0
  fi

  if [[ -s "$candidate_path" ]]; then
    newline_count="$(tail -c 1 "$candidate_path" 2>/dev/null | wc -l | tr -d '[:space:]')"
    if [[ "$newline_count" != "1" ]]; then
      printf '\n' >>"$candidate_path"
    fi
  fi

  printf '%s\n' "$SSH_PUBLIC_KEY" >>"$candidate_path"
}

apply_authorized_keys() {
  local candidate_path=""

  ensure_not_symlink "$TARGET_SSH_DIR"
  ensure_not_symlink "$AUTHORIZED_KEYS_PATH"

  candidate_path="$(mktemp)"
  build_authorized_keys_candidate "$candidate_path"

  if [[ "$(id -u)" -eq "$TARGET_UID" ]]; then
    mkdir -p -- "$TARGET_SSH_DIR"
    chmod 0700 "$TARGET_SSH_DIR"
    install -m 0600 "$candidate_path" "$AUTHORIZED_KEYS_PATH"
    chgrp "$TARGET_GROUP" "$TARGET_SSH_DIR" "$AUTHORIZED_KEYS_PATH"
  else
    require_sudo_access
    sudo_run install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_SSH_DIR"
    sudo_run install -m 0600 -o "$TARGET_USER" -g "$TARGET_GROUP" "$candidate_path" "$AUTHORIZED_KEYS_PATH"
    sudo_run chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_SSH_DIR" "$AUTHORIZED_KEYS_PATH"
    sudo_run chmod 0700 "$TARGET_SSH_DIR"
    sudo_run chmod 0600 "$AUTHORIZED_KEYS_PATH"
  fi

  rm -f -- "$candidate_path"
  log_info "ensured authorized key is present for $TARGET_USER"
}

validate_sshd_config() {
  require_sudo_access
  sudo_run sshd -t -f "$SSHD_CONFIG_PATH"
}

enable_and_restart_ssh_service() {
  require_sudo_access
  log_info "enabling and starting ssh.service"
  sudo_run systemctl enable --now ssh.service
  if ! sudo_run systemctl reload ssh.service; then
    log_warn "reload failed; restarting ssh.service"
    sudo_run systemctl restart ssh.service
  fi
}

verify_authorized_keys_state() {
  local dir_state=""
  local file_state=""

  [[ -d "$TARGET_SSH_DIR" ]] || die "missing directory: $TARGET_SSH_DIR"
  [[ -f "$AUTHORIZED_KEYS_PATH" ]] || die "missing file: $AUTHORIZED_KEYS_PATH"
  grep -Fqx -- "$SSH_PUBLIC_KEY" "$AUTHORIZED_KEYS_PATH" || {
    die "authorized_keys does not contain SSH_PUBLIC_KEY"
  }

  dir_state="$(stat -c '%U:%G:%a' "$TARGET_SSH_DIR")"
  file_state="$(stat -c '%U:%G:%a' "$AUTHORIZED_KEYS_PATH")"

  [[ "$dir_state" == "${TARGET_USER}:${TARGET_GROUP}:700" ]] || {
    die "unexpected state for $TARGET_SSH_DIR: $dir_state"
  }
  [[ "$file_state" == "${TARGET_USER}:${TARGET_GROUP}:600" ]] || {
    die "unexpected state for $AUTHORIZED_KEYS_PATH: $file_state"
  }
}

verify_sshd_state() {
  local rendered_config=""

  require_sudo_access
  require_command sshd

  sudo_run test -f "$SSHD_DROPIN_PATH" || die "missing file: $SSHD_DROPIN_PATH"
  validate_sshd_config
  rendered_config="$(sudo_run sshd -T)"

  printf '%s\n' "$rendered_config" | grep -Fxq 'pubkeyauthentication yes' || {
    die "sshd effective config is missing 'pubkeyauthentication yes'"
  }
  printf '%s\n' "$rendered_config" | grep -Fxq 'authenticationmethods publickey' || {
    die "sshd effective config is missing 'authenticationmethods publickey'"
  }
  printf '%s\n' "$rendered_config" | grep -Fxq 'authorizedkeysfile .ssh/authorized_keys' || {
    die "sshd effective config is missing 'authorizedkeysfile .ssh/authorized_keys'"
  }
  printf '%s\n' "$rendered_config" | grep -Fxq 'passwordauthentication no' || {
    die "sshd effective config is missing 'passwordauthentication no'"
  }
  printf '%s\n' "$rendered_config" | grep -Fxq 'kbdinteractiveauthentication no' || {
    die "sshd effective config is missing 'kbdinteractiveauthentication no'"
  }
  printf '%s\n' "$rendered_config" | grep -Fxq 'permitemptypasswords no' || {
    die "sshd effective config is missing 'permitemptypasswords no'"
  }
  printf '%s\n' "$rendered_config" | grep -Fxq 'permitrootlogin no' || {
    die "sshd effective config is missing 'permitrootlogin no'"
  }
  printf '%s\n' "$rendered_config" | grep -Fxq "allowusers ${TARGET_USER}" || {
    die "sshd effective config is missing 'allowusers ${TARGET_USER}'"
  }

  sudo_run systemctl is-enabled ssh.service >/dev/null || die "ssh.service is not enabled"
  sudo_run systemctl is-active ssh.service >/dev/null || die "ssh.service is not active"
}

phase_doctor() {
  log_info "phase: doctor"
  detect_target_user
  load_env_file
  validate_public_key

  require_command awk
  require_command chgrp
  require_command cmp
  require_command dpkg-query
  require_command getent
  require_command grep
  require_command id
  require_command install
  require_command mktemp
  require_command ssh-keygen
  require_command stat
  require_command systemctl
  require_command tail
  require_command tr
  require_command wc

  if [[ "$(id -u)" -ne 0 ]]; then
    require_command sudo
  fi
}

phase_install() {
  log_info "phase: install"
  phase_doctor
  ensure_openssh_server
  require_command sshd
  ensure_sshd_include
  ensure_host_keys
  apply_sshd_dropin
  apply_authorized_keys
  validate_sshd_config
  enable_and_restart_ssh_service
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  require_command sshd
  verify_authorized_keys_state
  verify_sshd_state
}

main() {
  parse_args "$@"

  case "$PHASE" in
    doctor)
      phase_doctor
      ;;
    install)
      phase_install
      ;;
    verify)
      phase_verify
      ;;
    all)
      phase_install
      phase_verify
      ;;
    *)
      usage >&2
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
