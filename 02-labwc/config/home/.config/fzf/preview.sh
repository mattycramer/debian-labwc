#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

target="${1:-}"
[[ -n "$target" ]] || exit 0

if [[ -d "$target" ]]; then
  exec ls -la --color=always --group-directories-first -- "$target"
fi

mime_type="$(file --dereference --brief --mime-type -- "$target" 2>/dev/null || true)"
case "$mime_type" in
  text/*|*/json|*/xml|application/x-shellscript|application/javascript)
    nl -ba -- "$target" | sed -n '1,200p'
    ;;
  *)
    file --dereference --brief -- "$target"
    ;;
esac
