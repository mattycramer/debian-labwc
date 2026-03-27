[terminal]
vt = @GREETD_VT@
switch = true

[default_session]
command = "env HOME=/var/lib/greetd/greeter XDG_CACHE_HOME=/var/lib/greetd/greeter/.cache XDG_CONFIG_HOME=/var/lib/greetd/greeter/.config XDG_DATA_HOME=/var/lib/greetd/greeter/.local/share XDG_STATE_HOME=/var/lib/greetd/greeter/.local/state tuigreet --time --asterisks --cmd /usr/local/bin/debian-labwc-session --sessions /usr/share/wayland-sessions"
user = "greeter"
