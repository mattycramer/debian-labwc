#!/usr/bin/env bash

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log_info() {
  printf '[%s] INFO: %s\n' "$(timestamp)" "$*"
}

log_error() {
  printf '[%s] ERROR: %s\n' "$(timestamp)" "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

run_cmd() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    printf '[dry-run] %q' "$1"
    shift
    while (($#)); do
      printf ' %q' "$1"
      shift
    done
    printf '\n'
    return 0
  fi
  "$@"
}
