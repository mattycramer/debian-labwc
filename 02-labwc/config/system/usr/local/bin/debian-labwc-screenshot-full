#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

target_dir="$HOME/Pictures/Screenshots"
mkdir -p "$target_dir"
target_file="$target_dir/full-$(date +%Y%m%d-%H%M%S).png"
grim "$target_file"
wl-copy <"$target_file"
