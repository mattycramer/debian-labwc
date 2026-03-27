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
source "$SCRIPT_DIR/lib/dock.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh --phase doctor|install|render|verify|print-env|nuke|all [--yes]
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
  require_command curl
  require_command getent
  require_command install
  require_command awk
  require_command sha256sum
  require_command sed
  require_command dpkg-deb
  require_command runuser
}

phase_install() {
  log_info "phase: install"
  phase_doctor
  load_env_file
  detect_target_user
  apt_update
  install_crystal_dock_dependencies
  install_crystal_dock_package
  render_crystal_dock_config
}

phase_render() {
  log_info "phase: render"
  phase_doctor
  load_env_file
  detect_target_user
  render_crystal_dock_config
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  load_env_file
  detect_target_user
  verify_crystal_dock_install
}

phase_print_env() {
  log_info "phase: print-env"
  load_env_file
  sed -n '1,160p' "$ENV_FILE"
}

phase_nuke() {
  log_info "phase: nuke"
  phase_doctor
  load_env_file
  detect_target_user
  remove_crystal_dock_install
}

main() {
  parse_args "$@"
  case "$PHASE" in
    doctor) phase_doctor ;;
    install) phase_install ;;
    render) phase_render ;;
    verify) phase_verify ;;
    print-env) phase_print_env ;;
    nuke) phase_nuke ;;
    all)
      phase_install
      phase_verify
      ;;
    *)
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
