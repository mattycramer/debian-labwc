#!/usr/bin/env bash

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log_info() {
  printf '[%s] INFO: %s\n' "$(timestamp)" "$*"
}

log_warn() {
  printf '[%s] WARN: %s\n' "$(timestamp)" "$*" >&2
}

log_error() {
  printf '[%s] ERROR: %s\n' "$(timestamp)" "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

quote_cmd() {
  local rendered=""
  printf -v rendered '%q ' "$@"
  printf '%s' "${rendered% }"
}

run_cmd() {
  "$@"
}

run_mutating_cmd() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log_info "dry-run: $(quote_cmd "$@")"
    return 0
  fi
  "$@"
}
