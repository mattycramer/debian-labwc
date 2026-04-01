#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly MOUNTS_CONFIG_FILE="$SCRIPT_DIR/mounts.conf"

PHASE="all"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/apt.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/accounts.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/detect.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/mount_units.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/permissions.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/secureboot.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/sudoers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/verify.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh --phase doctor|sid|mounts|permissions|secureboot|sudoers|verify|print-env|nuke|all
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

require_make_wrapper() {
  [[ "${SYSTEM_MAKE_WRAPPER:-}" == "1" ]] || {
    die "run this installer via 'make <target>' from 00-system; do not call install.sh directly"
  }
}

phase_doctor() {
  log_info "phase: doctor"
  run_preflight_checks 1
}

phase_sid() {
  log_info "phase: sid"
  phase_doctor
  apply_managed_sid_repository
}

run_preflight_checks() {
  local validate_configs="${1:-1}"

  require_root
  require_debian_trixie
  require_amd64
  require_command awk
  require_command chmod
  require_command chown
  require_command cmp
  require_command cp
  require_command apt
  require_command apt-cache
  require_command apt-get
  require_command dpkg
  require_command dpkg-query
  require_command find
  require_command findmnt
  require_command getent
  require_command grep
  require_command groupadd
  require_command id
  require_command install
  require_command journalctl
  require_command lsblk
  require_command mktemp
  require_command modinfo
  require_command nologin
  require_command readlink
  require_command sed
  require_command stat
  require_command systemctl
  require_command systemd-analyze
  require_command systemd-escape
  require_command useradd
  require_command usermod
  detect_target_user
  require_supported_sudoers_user
  resolve_visudo_bin
  resolve_sudoers_dropin_path
  require_file "$SYSTEM_SUDOERS_PATH"
  sudoers_includes_dropin_dir || die "$SYSTEM_SUDOERS_PATH must include $SYSTEM_SUDOERS_D_PATH"
  require_dir "$SYSTEM_TARGET_HOME"
  if [[ "$validate_configs" -eq 1 ]]; then
    require_file "$MOUNTS_CONFIG_FILE"
    validate_managed_mount_units
    validate_managed_sudoers_policy
  fi
}

phase_mounts() {
  log_info "phase: mounts"
  phase_doctor
  apply_managed_mount_units
}

phase_permissions() {
  log_info "phase: permissions"
  phase_doctor
  apply_system_account_policies
  apply_system_path_permissions
  apply_home_permissions
}

phase_secureboot() {
  log_info "phase: secureboot"
  phase_doctor
  apply_managed_secure_boot
}

phase_sudoers() {
  log_info "phase: sudoers"
  phase_doctor
  apply_managed_sudoers
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  verify_install
}

phase_print_env() {
  log_info "phase: print-env"
  detect_target_user
  require_supported_sudoers_user
  resolve_sudoers_dropin_path
  print_resolved_config
}

phase_nuke() {
  log_info "phase: nuke"
  run_preflight_checks 0
  remove_managed_sid_repository
  remove_managed_secure_boot
  remove_managed_mount_units
  remove_managed_sudoers
  log_warn "directory ownership and permissions are intentionally left in place"
}

main() {
  parse_args "$@"
  require_make_wrapper
  case "$PHASE" in
    doctor) phase_doctor ;;
    sid) phase_sid ;;
    mounts) phase_mounts ;;
    permissions) phase_permissions ;;
    secureboot) phase_secureboot ;;
    sudoers) phase_sudoers ;;
    verify) phase_verify ;;
    print-env) phase_print_env ;;
    nuke) phase_nuke ;;
    install|all)
      phase_doctor
      phase_sid
      phase_permissions
      phase_mounts
      phase_secureboot
      phase_sudoers
      phase_verify
      ;;
    *)
      usage >&2
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
