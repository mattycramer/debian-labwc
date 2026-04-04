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
source "$SCRIPT_DIR/lib/maintenance.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/verify.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh --phase doctor|detect|packages|render|enable|verify|print-env|nuke|all [--yes]
EOF
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
  require_command runuser
  require_command systemctl
  require_command findmnt
  require_command lsblk
  require_command blkid
  require_command git
  require_command timeout
  require_command update-grub
  require_command grub-script-check
}

phase_detect() {
  log_info "phase: detect"
  phase_doctor
  load_env_file
  detect_host_layout "$ENV_FILE"
}

phase_packages() {
  log_info "phase: packages"
  phase_doctor
  load_env_file
  apt_update
  install_maintenance_packages
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
  load_env_file
  enable_all_services
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  load_env_file
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
  remove_maintenance_install
}

main() {
  parse_args "$@"
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
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
