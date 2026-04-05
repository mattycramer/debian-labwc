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
source "$SCRIPT_DIR/lib/apt.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/detect.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/broker.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/verify.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh --phase doctor|detect|packages|render|enable|verify|print-env|nuke|all [--yes]
EOF
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
    detect|packages|render|enable|verify|all)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

install_method_is_source() {
  [[ "${DBUS_BROKER_INSTALL_METHOD:-}" == "source" ]]
}

current_install_method() {
  local value
  value="$(read_env_value "DBUS_BROKER_INSTALL_METHOD")"
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

  if [[ -r /dev/tty && -w /dev/tty ]]; then
    while true; do
      printf '%s' "Do you want to compile and install dbus-broker from source? [Y/n] " >/dev/tty
      IFS= read -r answer </dev/tty || die "DBUS_BROKER_INSTALL_METHOD is unset in $ENV_FILE and the terminal prompt could not be read from /dev/tty"
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
          printf '%s\n' "Please answer Y or n." >/dev/tty
          ;;
      esac
    done
  fi

  if [[ -t 0 && -t 1 ]]; then
    while true; do
      IFS= read -r -p "Do you want to compile and install dbus-broker from source? [Y/n] " answer
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
  fi

  die "DBUS_BROKER_INSTALL_METHOD is unset in $ENV_FILE and no interactive terminal is available to choose source or artifact install mode"
}

ensure_install_method_in_env() {
  local selected_method=""

  install_method_prompt_required_for_phase || return 0
  [[ -f "$ENV_FILE" ]] || die "missing env file: $ENV_FILE"

  if [[ "$PHASE" == "all" ]]; then
    selected_method="$(prompt_install_method)"
    write_env_value "DBUS_BROKER_INSTALL_METHOD" "$selected_method"
    return 0
  fi

  selected_method="$(current_install_method)"
  if [[ -n "$selected_method" ]]; then
    return 0
  fi

  selected_method="$(prompt_install_method)"
  write_env_value "DBUS_BROKER_INSTALL_METHOD" "$selected_method"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --phase)
        [[ $# -ge 2 ]] || die "missing value for --phase"
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
  require_command apt-cache
  require_command awk
  require_command chmod
  require_command chown
  require_command cmp
  require_command cp
  require_command curl
  require_command date
  require_command dpkg-query
  require_command find
  require_command getent
  require_command grep
  require_command id
  require_command install
  require_command journalctl
  require_command mktemp
  require_command mv
  require_command python3
  require_command readlink
  require_command rm
  require_command runuser
  require_command sed
  require_command sha256sum
  require_command ps
  require_command stat
  require_command strings
  require_command systemctl
  require_command systemd-analyze
  require_command tar
  require_command rmdir
}

phase_build_doctor() {
  require_command clang
  require_command clang++
  require_command ld.lld
  require_command git
  require_command meson
  require_command ninja
  require_command bindgen
  require_command rustup
  require_command ldd
}

phase_detect() {
  log_info "phase: detect"
  phase_doctor
  load_env_file
  detect_install_context "$ENV_FILE"
}

phase_packages() {
  log_info "phase: packages"
  phase_doctor
  load_env_file
  require_managed_apt_sources
  apt_update
  install_dbus_runtime_packages
}

phase_render() {
  log_info "phase: render"
  phase_doctor
  load_env_file
  validate_env_settings
  if install_method_is_source; then
    phase_build_doctor
  fi
  trap 'cleanup_build_workspace' RETURN
  if install_method_is_source; then
    prepare_source_build
    install_source_build
  else
    prepare_artifact_install
    install_artifact_build
  fi
  render_managed_units
  trap - RETURN
  cleanup_build_workspace
}

phase_enable() {
  log_info "phase: enable"
  phase_doctor
  load_env_file
  validate_env_settings
  enable_broker_runtime
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  load_env_file
  if install_method_is_source; then
    phase_build_doctor
  fi
  validate_env_settings
  verify_install
}

phase_print_env() {
  log_info "phase: print-env"
  load_env_file
  print_env_redacted "$ENV_FILE"
}

phase_nuke() {
  log_info "phase: nuke"
  phase_doctor
  load_env_file
  validate_env_settings
  remove_broker_install
}

main() {
  parse_args "$@"
  ensure_install_method_in_env
  case "$PHASE" in
    doctor) phase_doctor ;;
    detect) phase_detect ;;
    packages) phase_packages ;;
    render) phase_render ;;
    enable) phase_enable ;;
    verify) phase_verify ;;
    print-env) phase_print_env ;;
    nuke) phase_nuke ;;
    all)
      phase_doctor
      phase_detect
      phase_packages
      phase_render
      phase_enable
      phase_verify
      ;;
    *)
      usage >&2
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
