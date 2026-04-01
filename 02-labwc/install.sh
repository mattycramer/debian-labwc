#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ENV_FILE="$SCRIPT_DIR/.env"

ASSUME_YES=1
PHASE="all"
export ASSUME_YES

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/templates.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/apt.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/detect.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/render.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/services.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/tweaks.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/keepsecret.sh"
usage() {
  cat <<'EOF'
Usage: ./install.sh --phase doctor|detect|packages|render|enable|extras|print-env|nuke|all [--yes]
EOF
}

gpg_prompt_required_for_phase() {
  case "$PHASE" in
    all|enable) return 0 ;;
    *) return 1 ;;
  esac
}

wireguard_configs_present() {
  [[ -d "$SCRIPT_DIR/config/wireguard" ]] || return 1
  compgen -G "$SCRIPT_DIR/config/wireguard/*.conf" >/dev/null
}

wireguard_prompt_required_for_phase() {
  case "$PHASE" in
    all|enable)
      wireguard_configs_present
      ;;
    *)
      return 1
      ;;
  esac
}

read_env_value() {
  local key="$1"
  python3 - "$ENV_FILE" "$key" <<'PY'
from pathlib import Path
import sys

env_path = Path(sys.argv[1])
key = sys.argv[2]

for line in env_path.read_text(encoding="utf-8").splitlines():
    if not line.startswith(f"{key}="):
        continue
    value = line.split("=", 1)[1].strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        value = bytes(value[1:-1], "utf-8").decode("unicode_escape")
    print(value, end="")
    break
PY
}

write_env_value() {
  local key="$1"
  local value="$2"
  local value_file

  value_file="$(mktemp)"
  printf '%s' "$value" >"$value_file"

  python3 - "$ENV_FILE" "$key" "$value_file" <<'PY'
from pathlib import Path
import sys

env_path = Path(sys.argv[1])
key = sys.argv[2]
value = Path(sys.argv[3]).read_text(encoding="utf-8")

escaped = (
    value
    .replace("\\", "\\\\")
    .replace('"', '\\"')
    .replace("$", "\\$")
    .replace("`", "\\`")
)

replacement = f'{key}="{escaped}"'
lines = env_path.read_text(encoding="utf-8").splitlines()

for index, line in enumerate(lines):
    if line.startswith(f"{key}="):
        lines[index] = replacement
        break
else:
    lines.append(replacement)

env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

  rm -f -- "$value_file"
}

ensure_gpg_password_in_env() {
  local current_value prompt_value confirm_value

  gpg_prompt_required_for_phase || return 0
  [[ -f "$ENV_FILE" ]] || die "missing env file: $ENV_FILE"

  current_value="$(read_env_value "KWALLET_SESSION_GPG_PASSWD")"
  [[ -z "$current_value" ]] || return 0
  [[ -t 0 && -t 1 ]] || die "KWALLET_SESSION_GPG_PASSWD is empty in $ENV_FILE and no interactive terminal is available for prompting"

  while true; do
    IFS= read -r -s -p "Enter GPG encryption password: " prompt_value
    printf '\n'
    IFS= read -r -s -p "Confirm GPG encryption password: " confirm_value
    printf '\n'

    [[ -n "$prompt_value" ]] || {
      printf '%s\n' "GPG encryption password cannot be empty." >&2
      continue
    }
    [[ "$prompt_value" == "$confirm_value" ]] || {
      printf '%s\n' "GPG encryption password confirmation did not match." >&2
      continue
    }
    [[ "$prompt_value" != *$'\n'* && "$prompt_value" != *$'\r'* ]] || die "GPG encryption password must not contain newlines"
    break
  done

  write_env_value "KWALLET_SESSION_GPG_PASSWD" "$prompt_value"
}

validate_wireguard_private_key() {
  local key="$1"
  python3 - "$key" <<'PY'
import base64
import sys

key = sys.argv[1].strip()

try:
    raw = base64.b64decode(key, validate=True)
except Exception as exc:  # noqa: BLE001
    raise SystemExit(f"invalid WireGuard private key encoding: {exc}")

if len(raw) != 32:
    raise SystemExit("WireGuard private key must decode to exactly 32 bytes")
PY
}

ensure_wireguard_private_key_in_env() {
  local current_value prompt_value confirm_value

  wireguard_prompt_required_for_phase || return 0
  [[ -f "$ENV_FILE" ]] || die "missing env file: $ENV_FILE"

  current_value="$(read_env_value "WIREGUARD_PRIV_KEY")"
  if [[ -n "$current_value" ]]; then
    validate_wireguard_private_key "$current_value" || die "WIREGUARD_PRIV_KEY in $ENV_FILE is invalid"
    return 0
  fi
  [[ -t 0 && -t 1 ]] || die "WIREGUARD_PRIV_KEY is empty in $ENV_FILE and no interactive terminal is available for prompting"

  while true; do
    IFS= read -r -s -p "Enter WireGuard private key: " prompt_value
    printf '\n'
    IFS= read -r -s -p "Confirm WireGuard private key: " confirm_value
    printf '\n'

    [[ -n "$prompt_value" ]] || {
      printf '%s\n' "WireGuard private key cannot be empty." >&2
      continue
    }
    [[ "$prompt_value" == "$confirm_value" ]] || {
      printf '%s\n' "WireGuard private key confirmation did not match." >&2
      continue
    }
    [[ "$prompt_value" != *$'\n'* && "$prompt_value" != *$'\r'* ]] || die "WireGuard private key must not contain newlines"
    if ! validate_wireguard_private_key "$prompt_value" >/dev/null 2>&1; then
      printf '%s\n' "WireGuard private key is not a valid 32-byte base64 key." >&2
      continue
    fi
    break
  done

  write_env_value "WIREGUARD_PRIV_KEY" "$prompt_value"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --phase)
        PHASE="${2:-}"
        shift 2
        ;;
      --yes)
        ASSUME_YES=1
        shift
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

load_env_file() {
  [[ -f "$ENV_FILE" ]] || die "missing env file: $ENV_FILE"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
}

phase_doctor() {
  log_info "phase: doctor"
  require_root
  require_debian_trixie
  require_amd64
  require_command apt
  require_command install
  require_command systemctl
  require_command lspci
  require_command getent
  require_command awk
  require_command python3
  require_command useradd
}

phase_detect() {
  log_info "phase: detect"
  phase_doctor
  detect_hardware "$ENV_FILE"
  load_env_file
}

phase_packages() {
  log_info "phase: packages"
  phase_doctor
  load_env_file
  require_sid_repository
  apt_update
  install_requested_packages
}

phase_render() {
  log_info "phase: render"
  phase_doctor
  load_env_file
  render_all_configs
}

phase_build_doctor() {
  require_command runuser
  require_command curl
  require_command tar
  require_command sha256sum
  require_command cmake
  require_command ctest
  require_command gcc
  require_command git
  require_command ninja
  require_command timeout
}

phase_enable() {
  log_info "phase: enable"
  phase_doctor
  require_command dbus-run-session
  require_command runuser
  require_command gpg
  require_command gpgconf
  require_command nmcli
  require_command fc-cache
  require_command fc-match
  require_command pinentry-gtk-2
  load_env_file
  bootstrap_target_user_gpg_key
  enable_all_services "$ENV_FILE"
}

phase_extras() {
  log_info "phase: extras"
  phase_doctor
  phase_build_doctor
  load_env_file
  install_labwc_tweaks
  install_keepsecret
}

phase_print_env() {
  log_info "phase: print-env"
  load_env_file
  sed -n '1,240p' "$ENV_FILE"
}

phase_nuke() {
  log_info "phase: nuke"
  phase_doctor
  load_env_file
  nuke_all_state
}

main() {
  parse_args "$@"
  ensure_gpg_password_in_env
  ensure_wireguard_private_key_in_env
  case "$PHASE" in
    doctor) phase_doctor ;;
    detect) phase_detect ;;
    packages) phase_packages ;;
    render) phase_render ;;
    enable) phase_enable ;;
    extras) phase_extras ;;
    print-env) phase_print_env ;;
    nuke) phase_nuke ;;
    all)
      phase_doctor
      phase_detect
      phase_packages
      phase_render
      phase_enable
      phase_extras
      ;;
    *)
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
