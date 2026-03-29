#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

workspace="${1:-}"

case "$workspace" in
  1|2|3|4) ;;
  *) exit 1 ;;
esac

command -v wlrctl >/dev/null 2>&1 || exit 0
exec wlrctl keyboard type "$workspace" SUPER
