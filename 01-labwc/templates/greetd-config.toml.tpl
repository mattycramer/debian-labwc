[terminal]
vt = 1

[default_session]
command = "env HOME=/var/cache/tuigreet XDG_CACHE_HOME=/var/cache/tuigreet/.cache XDG_STATE_HOME=/var/cache/tuigreet/.local/state tuigreet --time --asterisks --remember --remember-session --remember-user-session --cmd /usr/local/bin/debian-labwc-session --sessions /usr/share/wayland-sessions"
user = "greeter"
