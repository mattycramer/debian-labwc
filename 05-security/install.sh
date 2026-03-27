#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ENV_FILE="$SCRIPT_DIR/.env"

DRY_RUN=0
ASSUME_YES=1
PHASE="all"
export DRY_RUN ASSUME_YES

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/security.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh --phase doctor|install|verify|print-env|nuke|all [--dry-run] [--yes]
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --phase)
        PHASE="${2:-}"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
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
  require_command gpg
  require_command tar
  require_command awk
  require_command sed
  require_command python3
  require_command install
  require_command libtool
  require_command sudo
  require_command systemctl
  require_command openssl
  require_command make
  require_command sha256sum
  require_command ldconfig
}

phase_install() {
  log_info "phase: install"
  phase_doctor
  load_env_file
  detect_security_download_user
  apt_update
  install_bootstrap_packages
  install_crowdsec_repository
  apt_update
  install_crowdsec_packages
  install_latest_nftables
  install_latest_aide
  render_all_configs
  systemd_daemon_reload
  initialize_nftables
  initialize_crowdsec
  initialize_aide_database
  enable_security_services
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  load_env_file
  detect_security_download_user
  verify_security_install
}

phase_print_env() {
  log_info "phase: print-env"
  load_env_file
  sed -n '1,120p' "$ENV_FILE"
}

phase_nuke() {
  log_info "phase: nuke"
  phase_doctor
  load_env_file
  remove_security_install
}

main() {
  parse_args "$@"
  case "$PHASE" in
    doctor) phase_doctor ;;
    install) phase_install ;;
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
