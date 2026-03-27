#!/usr/bin/env bash

readonly LABWC_TWEAKS_BIN_PATH="/usr/bin/labwc-tweaks"
readonly LABWC_TWEAKS_DESKTOP_PATH="/usr/share/applications/labwc_tweaks.desktop"
readonly LABWC_TWEAKS_APPDATA_PATH="/usr/share/metainfo/labwc_tweaks.appdata.xml"
readonly LABWC_TWEAKS_ICON_PATH="/usr/share/icons/hicolor/scalable/apps/labwc_tweaks.svg"

labwc_tweaks_cache_root() {
  printf '%s/.cache/debian-labwc/labwc-tweaks\n' "$LABWC_TARGET_HOME"
}

labwc_tweaks_archive_path() {
  printf '%s/source.tar.gz\n' "$(labwc_tweaks_cache_root)"
}

labwc_tweaks_source_dir() {
  printf '%s/source\n' "$(labwc_tweaks_cache_root)"
}

labwc_tweaks_build_dir() {
  printf '%s/build\n' "$(labwc_tweaks_cache_root)"
}

prepare_labwc_tweaks_cache() {
  local cache_root
  cache_root="$(labwc_tweaks_cache_root)"
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" \
    "$LABWC_TARGET_HOME/.cache" \
    "$LABWC_TARGET_HOME/.cache/debian-labwc" \
    "$cache_root"
}

download_labwc_tweaks_source() {
  local archive_path
  archive_path="$(labwc_tweaks_archive_path)"
  prepare_labwc_tweaks_cache
  run_cmd runuser -u "$LABWC_TARGET_USER" -- sh -c "rm -f -- '$archive_path'"
  run_cmd runuser -u "$LABWC_TARGET_USER" -- env HOME="$LABWC_TARGET_HOME" curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 180 --silent --show-error -o "$archive_path" "$LABWC_TWEAKS_TARBALL_URL"
}

install_labwc_tweaks() {
  local archive_path source_dir build_dir
  archive_path="$(labwc_tweaks_archive_path)"
  source_dir="$(labwc_tweaks_source_dir)"
  build_dir="$(labwc_tweaks_build_dir)"

  [[ -n "${LABWC_TWEAKS_VERSION:-}" ]] || die "LABWC_TWEAKS_VERSION is required"
  [[ -n "${LABWC_TWEAKS_TAG:-}" ]] || die "LABWC_TWEAKS_TAG is required"
  [[ -n "${LABWC_TWEAKS_TARBALL_URL:-}" ]] || die "LABWC_TWEAKS_TARBALL_URL is required"

  download_labwc_tweaks_source

  run_cmd runuser -u "$LABWC_TARGET_USER" -- sh -c "rm -rf -- '$source_dir' '$build_dir' && mkdir -p '$source_dir' '$build_dir'"
  run_cmd runuser -u "$LABWC_TARGET_USER" -- tar -xzf "$archive_path" -C "$source_dir" --strip-components=1
  run_cmd runuser -u "$LABWC_TARGET_USER" -- env HOME="$LABWC_TARGET_HOME" cmake -S "$source_dir" -B "$build_dir" -G Ninja -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=/usr -W no-dev
  run_cmd runuser -u "$LABWC_TARGET_USER" -- env HOME="$LABWC_TARGET_HOME" cmake --build "$build_dir" --verbose
  run_cmd runuser -u "$LABWC_TARGET_USER" -- env HOME="$LABWC_TARGET_HOME" ctest --verbose --force-new-ctest-process --test-dir "$build_dir"
  run_cmd cmake --install "$build_dir"
}
