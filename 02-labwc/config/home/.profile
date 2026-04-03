# Managed by labwc
umask 022

if [ -f "$HOME/.config/system/profile.d/00-build-env.sh" ]; then
  # shellcheck disable=SC1090
  . "$HOME/.config/system/profile.d/00-build-env.sh"
fi

PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

path_prepend_unique() {
  [ -n "${1:-}" ] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

@MIGRATED_PATH_SNIPPET@

if [ -n "${COMPOSER_HOME:-}" ]; then
  path_prepend_unique "$COMPOSER_HOME/vendor/bin"
fi
if [ -n "${GEM_HOME:-}" ]; then
  path_prepend_unique "$GEM_HOME/bin"
fi
path_prepend_unique "${UV_TOOL_BIN_DIR:-}"
path_prepend_unique "${PNPM_HOME:-}"
path_prepend_unique "/pool/builds/node_modules/npm/bin"
path_prepend_unique "${GOBIN:-}"
if [ -n "${CARGO_HOME:-}" ]; then
  path_prepend_unique "$CARGO_HOME/bin"
fi
path_prepend_unique "$HOME/.local/bin"
path_prepend_unique "/usr/local/bin"
path_prepend_unique "/data/usr/local/bin"

export PATH

if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
  # shellcheck disable=SC1090
  case "$-" in
    *i*) . "$HOME/.bashrc" ;;
  esac
fi
