#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ENV_FILE="$SCRIPT_DIR/.env"

ASSUME_YES=1
DRY_RUN=0
PHASE="all"
export ASSUME_YES DRY_RUN

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/platform.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/repo.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/apt.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/render.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/verify.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh --phase doctor|repo|packages|config|verify|print-env|nuke|all [--yes] [--dry-run]
EOF
}

set_default_config() {
  NVIDIA_INSTALL="1"
  NVIDIA_UPSTREAM_DISTRO="auto"
  NVIDIA_KERNEL_MODULE_FLAVOR="proprietary"
  NVIDIA_DRIVER_PIN_PACKAGE="auto"
  CUDA_TOOLKIT_PACKAGE="cuda-toolkit"
  NVIDIA_INSTALL_SWITCHEROO_CONTROL="1"
  NVIDIA_ENABLE_DRM_MODESET="1"
}

parse_env_value() {
  local raw="$1"
  local line_number="$2"
  local value=""

  case "$raw" in
    \"*\")
      [[ "${#raw}" -ge 2 && "${raw: -1}" == "\"" ]] || die "invalid quoted value on line $line_number in $ENV_FILE"
      value="${raw:1:${#raw}-2}"
      ;;
    \'*\')
      [[ "${#raw}" -ge 2 && "${raw: -1}" == "'" ]] || die "invalid quoted value on line $line_number in $ENV_FILE"
      value="${raw:1:${#raw}-2}"
      ;;
    *)
      [[ "$raw" != *[[:space:]]* ]] || die "unquoted whitespace is not allowed on line $line_number in $ENV_FILE"
      value="$raw"
      ;;
  esac

  [[ "$value" != *'$('* ]] || die "command substitution is not allowed on line $line_number in $ENV_FILE"
  [[ "$value" != *'`'* ]] || die "backticks are not allowed on line $line_number in $ENV_FILE"
  [[ "$value" != *'${'* ]] || die "parameter expansion is not allowed on line $line_number in $ENV_FILE"

  printf '%s' "$value"
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
      --dry-run)
        DRY_RUN=1
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
  local line=""
  local line_number=0
  local key=""
  local raw_value=""
  local value=""

  set_default_config
  [[ -f "$ENV_FILE" ]] || die "missing env file: $ENV_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*($|#) ]] && continue
    [[ "$line" =~ ^([A-Z0-9_]+)=(.*)$ ]] || die "invalid env assignment on line $line_number in $ENV_FILE"
    key="${BASH_REMATCH[1]}"
    raw_value="${BASH_REMATCH[2]}"
    value="$(parse_env_value "$raw_value" "$line_number")"
    case "$key" in
      NVIDIA_INSTALL|NVIDIA_UPSTREAM_DISTRO|NVIDIA_KERNEL_MODULE_FLAVOR|NVIDIA_DRIVER_PIN_PACKAGE|CUDA_TOOLKIT_PACKAGE|NVIDIA_INSTALL_SWITCHEROO_CONTROL|NVIDIA_ENABLE_DRM_MODESET)
        printf -v "$key" '%s' "$value"
        ;;
      *)
        die "unsupported env key '$key' on line $line_number in $ENV_FILE"
        ;;
    esac
  done <"$ENV_FILE"
  validate_config
  resolve_platform_config
}

phase_doctor() {
  log_info "phase: doctor"
  phase_system_doctor
  require_nvidia_gpu_presence
}

phase_system_doctor() {
  load_env_file
  require_supported_debian
  require_amd64_architecture
  require_command apt
  require_command apt-get
  require_command apt-cache
  require_command dpkg
  require_command dpkg-query
  require_command awk
  require_command grep
  require_command install
  require_command mktemp
  require_command sed
  require_command uname
  require_file "$DEBIAN_ARCHIVE_KEYRING_PATH"
  verify_secure_boot_prerequisites
  log_platform_summary
}

phase_repo() {
  log_info "phase: repo"
  phase_doctor
  require_root
  require_debian_contrib_configured
  apt_update
  ensure_download_tool
  install_cuda_keyring_package
  apt_update
  verify_nvidia_upstream_repository
  install_optional_driver_pinning_package
}

phase_packages() {
  log_info "phase: packages"
  phase_repo
  verify_debian_prerequisite_repository
  install_debian_prerequisite_packages
  install_nvidia_stack
}

phase_config() {
  log_info "phase: config"
  phase_doctor
  require_root
  render_nvidia_module_config
  refresh_initramfs
}

phase_verify() {
  log_info "phase: verify"
  phase_doctor
  verify_installation
}

phase_print_env() {
  log_info "phase: print-env"
  load_env_file
  print_resolved_config
}

phase_nuke() {
  log_info "phase: nuke"
  phase_system_doctor
  require_root
  remove_nvidia_stack
  remove_nvidia_module_config
  remove_cuda_keyring_package
  apt_update
  refresh_initramfs
}

main() {
  parse_args "$@"
  case "$PHASE" in
    doctor) phase_doctor ;;
    repo) phase_repo ;;
    packages) phase_packages ;;
    config) phase_config ;;
    verify) phase_verify ;;
    print-env) phase_print_env ;;
    nuke) phase_nuke ;;
    install|all)
      phase_packages
      phase_config
      phase_verify
      ;;
    *)
      usage >&2
      die "unsupported phase: $PHASE"
      ;;
  esac
}

main "$@"
