#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

command -v foot >/dev/null 2>&1 || exit 1

foot -T "System Upgrade" -e bash -lc 'sudo apt upgrade; rc=$?; printf "\nPress Enter to close..."; read -r _; exit $rc'
pkill -RTMIN+12 -x waybar >/dev/null 2>&1 || true
