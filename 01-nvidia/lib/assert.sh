#!/usr/bin/env bash

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "run as root"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}

require_supported_debian() {
  local codename=""
  codename="$(debian_codename)"
  case "$codename" in
    bookworm|trixie) ;;
    *)
      die "expected Debian bookworm or trixie, found '${codename:-unknown}'"
      ;;
  esac
}

require_amd64_architecture() {
  local arch
  arch="$(dpkg --print-architecture)"
  [[ "$arch" == "amd64" ]] || die "expected amd64, found '$arch'"
}

require_boolean_setting() {
  local name="$1"
  local value="$2"
  [[ "$value" == "0" || "$value" == "1" ]] || die "$name must be 0 or 1, found '$value'"
}

require_value_in_set() {
  local name="$1"
  local value="$2"
  shift 2
  local allowed=""
  for allowed in "$@"; do
    [[ "$value" == "$allowed" ]] && return 0
  done
  die "$name must be one of: $*; found '$value'"
}

require_regex_match() {
  local name="$1"
  local value="$2"
  local pattern="$3"
  [[ "$value" =~ $pattern ]] || die "$name has an invalid value: '$value'"
}

require_nvidia_gpu_presence() {
  [[ "${NVIDIA_HAS_NVIDIA_GPU:-no}" == "yes" ]] || die "no NVIDIA GPU detected under /sys/bus/pci/devices"
}
