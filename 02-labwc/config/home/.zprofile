# Managed by labwc
umask 022
export PATH="/data/usr/local/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

if [ -f "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
