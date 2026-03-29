#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly FSTAB_ENV_FILE="$SCRIPT_DIR/fstab.env"

PHASE="all"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/detect.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/fstab.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/permissions.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/verify.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh --phase doctor|fstab|permissions|verify|print-env|nuke|all
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --phase)
        [[ $# -ge 2 ]] || die "missing value for --phase"
        PHASE="${2:-}"
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

phase_doctor() {
  log_info "phase: doctor"
  require_root
  require_debian_trixie
  require_amd64
  require_command awk
  require_command chmod
  require_command chown
  require_command cmp
  require_command dpkg
  require_command find
  require_command getent
  require_command id
  require_command install
  require_command mktemp
  require_command stat
  detect_target_user
  require_file "$SYSTEM_FSTAB_PATH"
  require_dir "$SYSTEM_TARGET_HOME"
  require_file "$FSTAB_ENV_FILE"
}

phase_fstab() {
  log_info "phase: fstab"
  phase_doctor
  apply_managed_fstab
}

phase_permissions() {
  log_info "phase: permissions"
  phase_doctor
  apply_system_path_permissions
  apply_home_permissions
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  verify_install
}

phase_print_env() {
  log_info "phase: print-env"
  detect_target_user
  print_resolved_config
}

phase_nuke() {
  log_info "phase: nuke"
  phase_doctor
  remove_managed_fstab
  log_warn "directory ownership and permissions are intentionally left in place"
}

main() {
  parse_args "$@"
  case "$PHASE" in
    doctor) phase_doctor ;;
    fstab) phase_fstab ;;
    permissions) phase_permissions ;;
    verify) phase_verify ;;
    print-env) phase_print_env ;;
    nuke) phase_nuke ;;
    install|all)
      phase_doctor
      phase_fstab
      phase_permissions
      phase_verify
      ;;
    *)
      usage >&2
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
