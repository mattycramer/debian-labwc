#!/usr/bin/env bash

readonly SYSTEM_FSTAB_PATH="/etc/fstab"
readonly SYSTEM_FSTAB_MANAGED_BEGIN="# >>> MANAGED BY debian-labwc 00-system >>>"
readonly SYSTEM_FSTAB_MANAGED_END="# <<< MANAGED BY debian-labwc 00-system <<<"

fstab_payload_has_entries() {
  awk '
    /^[[:space:]]*($|#)/ { next }
    { found = 1; exit 0 }
    END { exit(found ? 0 : 1) }
  ' "$FSTAB_ENV_FILE"
}

strip_managed_fstab_block() {
  local source_path="$1"
  local destination_path="$2"

  awk -v begin="$SYSTEM_FSTAB_MANAGED_BEGIN" -v end="$SYSTEM_FSTAB_MANAGED_END" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$source_path" >"$destination_path"
}

trim_trailing_blank_lines() {
  local source_path="$1"
  local destination_path="$2"

  awk '
    {
      lines[NR] = $0
      if ($0 !~ /^[[:space:]]*$/) {
        last = NR
      }
    }
    END {
      for (i = 1; i <= last; i++) {
        print lines[i]
      }
    }
  ' "$source_path" >"$destination_path"
}

canonical_fstab_entries() {
  local path="$1"

  awk '
    /^[[:space:]]*($|#)/ { next }
    NF >= 6 { printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6 }
  ' "$path"
}

render_filtered_payload() {
  local base_path="$1"
  local destination_path="$2"
  local existing_entries_path

  existing_entries_path="$(mktemp)"
  canonical_fstab_entries "$base_path" >"$existing_entries_path"

  # Preserve comment context only for entries that still need to be appended.
  awk -v existing_path="$existing_entries_path" '
    BEGIN {
      while ((getline line < existing_path) > 0) {
        existing[line] = 1
        split(line, fields, "\t")
        if (fields[2] != "none") {
          existing_target[fields[2]] = line
        }
      }
      close(existing_path)
    }
    {
      raw = $0
      sub(/\r$/, "", raw)

      if (raw ~ /^[[:space:]]*$/) {
        pending[++pending_count] = ""
        next
      }
      if (raw ~ /^[[:space:]]*#/) {
        pending[++pending_count] = raw
        next
      }

      if (NF < 6) {
        printf "invalid fstab entry on line %d in %s: expected at least 6 fields\n", NR, FILENAME > "/dev/stderr"
        exit 1
      }
      if (!($2 == "none" || $2 ~ /^\//)) {
        printf "invalid mountpoint on line %d in %s: %s\n", NR, FILENAME, $2 > "/dev/stderr"
        exit 1
      }
      if ($5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/) {
        printf "invalid dump/fsck fields on line %d in %s\n", NR, FILENAME > "/dev/stderr"
        exit 1
      }

      key = $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6
      if ($2 != "none" && ($2 in existing_target) && existing_target[$2] != key) {
        printf "conflicting existing fstab entry for mountpoint %s\n", $2 > "/dev/stderr"
        exit 1
      }
      if ($2 != "none" && ($2 in emitted_target) && emitted_target[$2] != key) {
        printf "conflicting payload fstab entry for mountpoint %s\n", $2 > "/dev/stderr"
        exit 1
      }
      if (existing[key] || emitted[key]) {
        pending_count = 0
        next
      }

      for (i = 1; i <= pending_count; i++) {
        print pending[i]
      }
      pending_count = 0

      print raw
      emitted[key] = 1
      if ($2 != "none") {
        emitted_target[$2] = key
      }
    }
  ' "$FSTAB_ENV_FILE" >"$destination_path" || {
    rm -f -- "$existing_entries_path"
    die "fstab payload validation failed"
  }

  rm -f -- "$existing_entries_path"
}

filtered_payload_has_entries() {
  local path="$1"

  awk '
    /^[[:space:]]*($|#)/ { next }
    { found = 1; exit 0 }
    END { exit(found ? 0 : 1) }
  ' "$path"
}

list_fstab_mountpoints() {
  awk '
    /^[[:space:]]*($|#)/ { next }
    NF >= 2 && $2 != "none" && $2 ~ /^\// { print $2 }
  ' "$FSTAB_ENV_FILE"
}

ensure_fstab_mountpoints() {
  local mountpoint
  while IFS= read -r mountpoint; do
    [[ -n "$mountpoint" ]] || continue
    run_cmd install -d -m 0755 -o root -g root "$mountpoint"
    run_cmd chown root:root "$mountpoint"
    run_cmd chmod 0755 "$mountpoint"
  done < <(list_fstab_mountpoints)
}

build_candidate_fstab() {
  local destination_path="$1"
  local include_payload="${2:-1}"
  local base_path trimmed_path filtered_payload_path

  base_path="$(mktemp)"
  trimmed_path="$(mktemp)"
  filtered_payload_path="$(mktemp)"

  strip_managed_fstab_block "$SYSTEM_FSTAB_PATH" "$base_path"
  trim_trailing_blank_lines "$base_path" "$trimmed_path"

  : >"$destination_path"
  if [[ -s "$trimmed_path" ]]; then
    cat "$trimmed_path" >"$destination_path"
  fi

  if [[ "$include_payload" -eq 1 ]]; then
    render_filtered_payload "$trimmed_path" "$filtered_payload_path"

    if filtered_payload_has_entries "$filtered_payload_path"; then
      if [[ -s "$destination_path" ]]; then
        printf '\n' >>"$destination_path"
      fi
      printf '%s\n' "$SYSTEM_FSTAB_MANAGED_BEGIN" >>"$destination_path"
      awk '{ sub(/\r$/, ""); print }' "$filtered_payload_path" >>"$destination_path"
      printf '%s\n' "$SYSTEM_FSTAB_MANAGED_END" >>"$destination_path"
    fi
  fi

  rm -f -- "$base_path" "$trimmed_path" "$filtered_payload_path"
}

apply_managed_fstab() {
  local candidate_path

  ensure_fstab_mountpoints
  candidate_path="$(mktemp)"
  build_candidate_fstab "$candidate_path" 1

  if cmp -s "$candidate_path" "$SYSTEM_FSTAB_PATH"; then
    log_info "/etc/fstab is already up to date"
    rm -f -- "$candidate_path"
    return 0
  fi

  run_cmd install -m 0644 "$candidate_path" "$SYSTEM_FSTAB_PATH"
  rm -f -- "$candidate_path"
  log_info "updated $SYSTEM_FSTAB_PATH"
}

remove_managed_fstab() {
  local candidate_path

  candidate_path="$(mktemp)"
  build_candidate_fstab "$candidate_path" 0

  if cmp -s "$candidate_path" "$SYSTEM_FSTAB_PATH"; then
    log_info "no managed fstab block present"
    rm -f -- "$candidate_path"
    return 0
  fi

  run_cmd install -m 0644 "$candidate_path" "$SYSTEM_FSTAB_PATH"
  rm -f -- "$candidate_path"
  log_info "removed managed entries from $SYSTEM_FSTAB_PATH"
}

verify_managed_fstab() {
  local candidate_path

  candidate_path="$(mktemp)"
  build_candidate_fstab "$candidate_path" 1
  cmp -s "$candidate_path" "$SYSTEM_FSTAB_PATH" || {
    rm -f -- "$candidate_path"
    die "$SYSTEM_FSTAB_PATH does not match the managed 00-system state"
  }
  rm -f -- "$candidate_path"
}
