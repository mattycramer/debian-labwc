# Managed by labwc
umask 022
export PATH="/data/usr/local/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
export EDITOR=nano
export VISUAL=nano
export HISTSIZE=10000
export HISTFILESIZE=20000

if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
  # shellcheck disable=SC1090
  . "$HOME/.bashrc"
fi
