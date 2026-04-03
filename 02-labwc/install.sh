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
source "$SCRIPT_DIR/lib/source_build.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/services.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/tweaks.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/keepsecret.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/verify.sh"
usage() {
  cat <<'EOF'
Usage: ./install.sh --phase doctor|detect|packages|render|build-sources|enable|verify|print-env|nuke|all [--yes]
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

install_method_prompt_required_for_phase() {
  case "$PHASE" in
    detect|packages|render|build-sources|enable|verify|all)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

install_method_is_source() {
  [[ "${LABWC_INSTALL_METHOD:-}" == "source" ]]
}

current_install_method() {
  local value
  value="$(read_env_value "LABWC_INSTALL_METHOD")"
  case "$value" in
    source|artifact)
      printf '%s\n' "$value"
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

prompt_install_method() {
  local answer=""

  [[ -t 0 && -t 1 ]] || die "LABWC_INSTALL_METHOD is unset in $ENV_FILE and no interactive terminal is available to choose source or artifact install mode"
  while true; do
    IFS= read -r -p "Do you want to build from source? [Y/n] " answer
    case "${answer:-Y}" in
      Y|y|yes|YES)
        printf '%s\n' "source"
        return 0
        ;;
      N|n|no|NO)
        printf '%s\n' "artifact"
        return 0
        ;;
      *)
        printf '%s\n' "Please answer Y or n." >&2
        ;;
    esac
  done
}

ensure_install_method_in_env() {
  local selected_method=""

  install_method_prompt_required_for_phase || return 0
  [[ -f "$ENV_FILE" ]] || die "missing env file: $ENV_FILE"

  selected_method="$(current_install_method)"
  if [[ "$PHASE" == "all" ]]; then
    selected_method="$(prompt_install_method)"
    write_env_value "LABWC_INSTALL_METHOD" "$selected_method"
    return 0
  fi
  if [[ -n "$selected_method" ]]; then
    return 0
  fi

  selected_method="$(prompt_install_method)"
  write_env_value "LABWC_INSTALL_METHOD" "$selected_method"
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
  local current_value

  wireguard_prompt_required_for_phase || return 0
  [[ -f "$ENV_FILE" ]] || die "missing env file: $ENV_FILE"

  current_value="$(read_env_value "WIREGUARD_PRIV_KEY")"
  if [[ -n "$current_value" ]]; then
    validate_wireguard_private_key "$current_value" || die "WIREGUARD_PRIV_KEY in $ENV_FILE is invalid"
    return 0
  fi
  log_info "No WireGuard private key provided. You must manually enter the private key in the installed generated WireGuard configs if you want VPN to work."
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
  require_command mktemp
  require_command mv
  require_command python3
  require_command curl
  require_command sha256sum
  require_command tar
  require_command useradd
  require_command usermod
}

phase_source_build_doctor() {
  require_command git
  require_command clang
  require_command clang++
  require_command ld.lld
  require_command rustup
  require_command cmake
  require_command ninja
  require_command pkg-config
  require_command ldd
  require_command grep
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

phase_enable() {
  log_info "phase: enable"
  phase_doctor
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

phase_build_sources() {
  log_info "phase: build-sources"
  phase_doctor
  load_env_file
  if install_method_is_source; then
    phase_source_build_doctor
    install_regreet_binary
    install_labwc_tweaks
    install_keepsecret
    return 0
  fi

  install_regreet_artifact
  install_labwc_tweaks_artifact
  install_keepsecret_artifact
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  load_env_file
  if install_method_is_source; then
    phase_source_build_doctor
  fi
  verify_install
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
  ensure_install_method_in_env
  ensure_gpg_password_in_env
  ensure_wireguard_private_key_in_env
  case "$PHASE" in
    doctor) phase_doctor ;;
    detect) phase_detect ;;
    packages) phase_packages ;;
    render) phase_render ;;
    build-sources) phase_build_sources ;;
    enable) phase_enable ;;
    verify) phase_verify ;;
    print-env) phase_print_env ;;
    nuke) phase_nuke ;;
    all)
      phase_doctor
      phase_detect
      phase_packages
      phase_render
      phase_build_sources
      phase_enable
      phase_verify
      ;;
    *)
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
