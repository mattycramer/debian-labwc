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
  require_command uname
}

phase_install() {
  log_info "phase: install"
  phase_doctor
  load_env_file
  apt_update
  install_nvidia_packages
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  verify_nvidia_install
}

phase_nuke() {
  log_info "phase: nuke"
  phase_doctor
  apt_update
  remove_nvidia_packages
}

main() {
  parse_args "$@"
  case "$PHASE" in
    doctor) phase_doctor ;;
    verify) phase_verify ;;
    nuke) phase_nuke ;;
    install|all)
      phase_install
      phase_verify
      ;;
    *)
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
