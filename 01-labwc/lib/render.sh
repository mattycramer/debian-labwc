#!/usr/bin/env bash

render_user_file() {
  local destination="$1"
  local content="$2"
  run_cmd install -D -m 0644 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$destination"
}

render_user_private_file() {
  local destination="$1"
  local content="$2"
  run_cmd install -D -m 0600 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$destination"
  run_cmd chmod 0600 "$destination"
}

render_user_script() {
  local destination="$1"
  local content="$2"
  run_cmd install -D -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" /dev/null "$destination"
  printf '%s' "$content" >"$destination"
  run_cmd chown "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$destination"
  run_cmd chmod 0755 "$destination"
}

render_labwc_environment() {
  local environment_file
  environment_file="$(cat <<EOF
XCURSOR_THEME=${LABWC_XCURSOR_THEME}
XCURSOR_SIZE=${LABWC_XCURSOR_SIZE}
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/labwc/environment" "$environment_file"
}

primary_wallpaper_source_path() {
  local wallpaper_path=""
  wallpaper_path="$(
    find "$SCRIPT_DIR/wallpaper" -maxdepth 1 -type f | sort | head -n 1
  )"
  [[ -n "$wallpaper_path" ]] || die "missing wallpaper asset under '$SCRIPT_DIR/wallpaper'"
  printf '%s\n' "$wallpaper_path"
}

primary_wallpaper_target_path() {
  local wallpaper_source_path
  wallpaper_source_path="$(primary_wallpaper_source_path)"
  printf '%s/.local/share/debian-labwc/%s\n' "$LABWC_TARGET_HOME" "$(basename "$wallpaper_source_path")"
}

ensure_user_base_dirs() {
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" \
    "$LABWC_TARGET_HOME/.config" \
    "$LABWC_TARGET_HOME/.local" \
    "$LABWC_TARGET_HOME/.local/share" \
    "$LABWC_TARGET_HOME/.local/state"
  run_cmd chown -R "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.config" "$LABWC_TARGET_HOME/.local"
}

render_home_dirs() {
  local -a dirs=(
    "$LABWC_TARGET_HOME/Desktop"
    "$LABWC_TARGET_HOME/Downloads"
    "$LABWC_TARGET_HOME/Templates"
    "$LABWC_TARGET_HOME/Public"
    "$LABWC_TARGET_HOME/Documents"
    "$LABWC_TARGET_HOME/Music"
    "$LABWC_TARGET_HOME/Pictures"
    "$LABWC_TARGET_HOME/Videos"
  )
  local dir
  for dir in "${dirs[@]}"; do
    run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$dir"
  done
  render_user_file "$LABWC_TARGET_HOME/.config/user-dirs.dirs" $'XDG_DESKTOP_DIR="$HOME/Desktop"\nXDG_DOWNLOAD_DIR="$HOME/Downloads"\nXDG_TEMPLATES_DIR="$HOME/Templates"\nXDG_PUBLICSHARE_DIR="$HOME/Public"\nXDG_DOCUMENTS_DIR="$HOME/Documents"\nXDG_MUSIC_DIR="$HOME/Music"\nXDG_PICTURES_DIR="$HOME/Pictures"\nXDG_VIDEOS_DIR="$HOME/Videos"\n'
  render_user_file "$LABWC_TARGET_HOME/.config/user-dirs.locale" $'en_US.UTF-8\n'
}

render_shell_startup_files() {
  local bashrc profile zshrc zprofile starship nanorc
  bashrc="$(cat <<'EOF'
# Managed by debian-labwc
umask 022
export PATH="/data/usr/local/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
export EDITOR=nano
export VISUAL=nano
export HISTSIZE=10000
export HISTFILESIZE=20000

alias ll='ls -alFh'
alias la='ls -A'

if [[ -f /etc/bash_completion ]]; then
  # shellcheck disable=SC1091
  source /etc/bash_completion
elif [[ -f /usr/share/bash-completion/bash_completion ]]; then
  # shellcheck disable=SC1091
  source /usr/share/bash-completion/bash_completion
fi

if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_OPTS_FILE="$HOME/.config/fzf/default-opts"
  export FZF_CTRL_R_OPTS="--prompt 'History> ' --border-label='Command History'"
fi

if command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
  export FZF_DEFAULT_COMMAND='fdfind --hidden --follow --exclude .git .'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fdfind --type d --hidden --follow --exclude .git .'
  export FZF_CTRL_T_OPTS="--prompt 'Files> ' --preview '$HOME/.config/fzf/preview.sh {}' --preview-window=right,60%,border-left,wrap"
  export FZF_ALT_C_OPTS="--prompt 'Directories> ' --preview 'ls -la --color=always -- {}' --preview-window=right,50%,border-left"
  export FZF_COMPLETION_OPTS='--border --info=inline-right'
  export FZF_COMPLETION_PATH_OPTS="--preview '$HOME/.config/fzf/preview.sh {}' --preview-window=right,60%,border-left,wrap"
  export FZF_COMPLETION_DIR_OPTS="--preview 'ls -la --color=always -- {}' --preview-window=right,50%,border-left"
fi

if [[ -r /usr/share/doc/fzf/examples/key-bindings.bash ]]; then
  # shellcheck disable=SC1091
  source /usr/share/doc/fzf/examples/key-bindings.bash
fi
if [[ -r /usr/share/doc/fzf/examples/completion.bash ]]; then
  # shellcheck disable=SC1091
  source /usr/share/doc/fzf/examples/completion.bash
fi

if command -v fdfind >/dev/null 2>&1; then
  _fzf_compgen_path() {
    local base_dir="${1:-.}"
    (
      builtin cd -- "$base_dir" 2>/dev/null &&
        command fdfind --hidden --follow --exclude .git .
    )
  }

  _fzf_compgen_dir() {
    local base_dir="${1:-.}"
    (
      builtin cd -- "$base_dir" 2>/dev/null &&
        command fdfind --type d --hidden --follow --exclude .git .
    )
  }
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
EOF
)"
  profile="$(cat <<'EOF'
# Managed by debian-labwc
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
EOF
)"
  zshrc="$(cat <<'EOF'
# Managed by debian-labwc
umask 022
export PATH="/data/usr/local/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
export EDITOR=nano
export VISUAL=nano
export HISTSIZE=10000
export HISTFILESIZE=20000
SAVEHIST="${HISTFILESIZE}"

alias ll='ls -alFh'
alias la='ls -A'

autoload -Uz compinit
compinit

if [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_OPTS_FILE="$HOME/.config/fzf/default-opts"
  export FZF_CTRL_R_OPTS="--prompt 'History> ' --border-label='Command History'"
fi

if command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
  export FZF_DEFAULT_COMMAND='fdfind --hidden --follow --exclude .git .'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fdfind --type d --hidden --follow --exclude .git .'
  export FZF_CTRL_T_OPTS="--prompt 'Files> ' --preview '$HOME/.config/fzf/preview.sh {}' --preview-window=right,60%,border-left,wrap"
  export FZF_ALT_C_OPTS="--prompt 'Directories> ' --preview 'ls -la --color=always -- {}' --preview-window=right,50%,border-left"
  export FZF_COMPLETION_OPTS='--border --info=inline-right'
  export FZF_COMPLETION_PATH_OPTS="--preview '$HOME/.config/fzf/preview.sh {}' --preview-window=right,60%,border-left,wrap"
  export FZF_COMPLETION_DIR_OPTS="--preview 'ls -la --color=always -- {}' --preview-window=right,50%,border-left"
fi

if [[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
  source /usr/share/doc/fzf/examples/key-bindings.zsh
fi
if [[ -r /usr/share/doc/fzf/examples/completion.zsh ]]; then
  source /usr/share/doc/fzf/examples/completion.zsh
fi

if command -v fdfind >/dev/null 2>&1; then
  _fzf_compgen_path() {
    local base_dir="${1:-.}"
    (
      builtin cd -- "$base_dir" 2>/dev/null &&
        command fdfind --hidden --follow --exclude .git .
    )
  }

  _fzf_compgen_dir() {
    local base_dir="${1:-.}"
    (
      builtin cd -- "$base_dir" 2>/dev/null &&
        command fdfind --type d --hidden --follow --exclude .git .
    )
  }
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
EOF
)"
  zprofile="$(cat <<'EOF'
# Managed by debian-labwc
umask 022
export PATH="/data/usr/local/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

if [ -f "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
EOF
)"
  starship="$(cat <<'EOF'
add_newline = false
format = "$username$hostname$directory$git_branch$git_status\n$character "

[username]
show_always = true
format = "[$user@](bold yellow)"

[hostname]
ssh_only = false
format = "[$hostname ](bold blue)"

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"

[directory]
format = "[$path ](bold cyan)"
home_symbol = "~"
truncation_length = 3
truncate_to_repo = false

[git_branch]
format = "[git:$branch ](bold magenta)"

[git_status]
format = "[$all_status$ahead_behind ](bold red)"
EOF
)"
  nanorc="$(cat <<'EOF'
set mouse
set autoindent
set tabsize 4
set tabstospaces
set softwrap
set indicator
set titlecolor bold,white,blue
set numbercolor cyan
set keycolor cyan
set functioncolor green
include "/usr/share/nano/*.nanorc"
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.bashrc" "$bashrc"
  render_user_file "$LABWC_TARGET_HOME/.profile" "$profile"
  render_user_file "$LABWC_TARGET_HOME/.zshrc" "$zshrc"
  render_user_file "$LABWC_TARGET_HOME/.zprofile" "$zprofile"
  render_user_file "$LABWC_TARGET_HOME/.config/starship.toml" "$starship"
  render_user_file "$LABWC_TARGET_HOME/.nanorc" "$nanorc"
}

render_xfce_helpers() {
  render_user_file "$LABWC_TARGET_HOME/.config/xfce4/helpers.rc" $'TerminalEmulator=foot\n'
}

render_tmux_config() {
  local tmux_conf
  tmux_conf="$(cat <<'EOF'
# Managed by debian-labwc
set -g default-terminal "tmux-256color"
set -as terminal-features ",foot*:RGB,ccolour,cstyle,extkeys,focus,title,clipboard"
set -as terminal-features ",foot-direct*:RGB,ccolour,cstyle,extkeys,focus,title,clipboard"
set -as terminal-features ",xterm-256color:RGB"
set -g focus-events on
set -g mouse on
set -g history-limit 100000
set -g renumber-windows on
set -g base-index 1
setw -g pane-base-index 1
setw -g mode-keys vi
set -g status-keys vi
set -s escape-time 10
set -g set-clipboard external
set -g detach-on-destroy off
set -g allow-rename off
set -g bell-action none

set -g status-position bottom
set -g status-interval 5
set -g status-left-length 40
set -g status-right-length 80
set -g status-style "fg=#d8dee9,bg=#111827"
set -g status-left "#S "
set -g status-right "%Y-%m-%d %H:%M "
set -g window-status-format " #I:#W "
set -g window-status-current-format " #I:#W* "
set -g window-status-current-style "fg=#111827,bg=#f6bd60,bold"
set -g pane-border-style "fg=#4b5563"
set -g pane-active-border-style "fg=#6dc4ed"
set -g message-style "fg=#111827,bg=#f6bd60,bold"
set -g message-command-style "fg=#111827,bg=#8ecae6"

bind r source-file ~/.tmux.conf \; display-message "tmux.conf reloaded"
bind c new-window -c "#{pane_current_path}"
bind '"' split-window -v -c "#{pane_current_path}"
bind % split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind | split-window -h -c "#{pane_current_path}"
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

bind-key -T copy-mode-vi v send -X begin-selection
bind-key -T copy-mode-vi y send -X copy-pipe-and-cancel "wl-copy"
bind-key -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-and-cancel "wl-copy"
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.tmux.conf" "$tmux_conf"
}

render_fzf_config() {
  local fzf_default_opts fzf_preview
  fzf_default_opts="$(cat <<'EOF'
--layout=reverse
--height=60%
--min-height=20
--border=rounded
--info=inline-right
--prompt=> 
--pointer=>
--marker=*
--scrollbar=|
--cycle
--ansi
--bind=ctrl-z:ignore
--bind=ctrl-/:toggle-preview
--bind=ctrl-space:toggle
--bind=ctrl-a:select-all
--bind=ctrl-d:deselect-all
--bind=ctrl-u:preview-half-page-up
--bind=ctrl-f:preview-half-page-down
--preview-window=right,60%,border-left,wrap
--color=bg:#0f1720,bg+:#1f2937,fg:#e5e7eb,fg+:#f8fafc,border:#475569,preview-border:#475569,spinner:#f6bd60,hl:#8ecae6,hl+:#6dc4ed,marker:#f6bd60,pointer:#f6bd60,prompt:#f6bd60,info:#94d2bd,header:#c4b5fd
EOF
)"
  fzf_preview="$(cat <<'EOF'
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
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/fzf/default-opts" "$fzf_default_opts"
  render_user_script "$LABWC_TARGET_HOME/.config/fzf/preview.sh" "$fzf_preview"
}

render_labwc_rc_xml() {
  case "${LABWC_NATURAL_SCROLL:-}" in
    yes|no) ;;
    *) die "LABWC_NATURAL_SCROLL must be 'yes' or 'no', found '${LABWC_NATURAL_SCROLL:-}'" ;;
  esac
  local title_bind
  title_bind="$(cat <<'EOF'
    <context name="Title">
      <mousebind button="Left" action="DoubleClick">
        <action name="ToggleMaximize" />
      </mousebind>
    </context>
EOF
)"
  local rc_xml
  rc_xml="$(cat <<EOF
<?xml version="1.0"?>
<labwc_config>
  <focus>
    <followMouse>${LABWC_FOLLOW_MOUSE}</followMouse>
    <followMouseRequiresMovement>no</followMouseRequiresMovement>
    <raiseOnFocus>${LABWC_RAISE_ON_FOCUS}</raiseOnFocus>
    <focusDelay>${LABWC_FOCUS_DELAY_MS}</focusDelay>
  </focus>
  <windowSwitcher preview="yes" outlines="yes" unshade="yes" order="focus">
    <osd show="yes" style="classic" output="focused" />
  </windowSwitcher>
  <mouse>
    <default />
    <doubleClickTime>${LABWC_DOUBLECLICK_TIME_MS}</doubleClickTime>
    <context name="Root">
      <mousebind button="Left" action="Press">
        <action name="Unfocus" />
      </mousebind>
    </context>
${title_bind}
  </mouse>
  <libinput>
    <device category="default">
      <naturalScroll>${LABWC_NATURAL_SCROLL}</naturalScroll>
    </device>
    <device category="touchpad">
      <naturalScroll>${LABWC_NATURAL_SCROLL}</naturalScroll>
    </device>
    <device category="non-touch">
      <naturalScroll>no</naturalScroll>
    </device>
  </libinput>
  <desktops>
    <popupTime>1000</popupTime>
    <names>
      <name>1</name>
      <name>2</name>
      <name>3</name>
      <name>4</name>
    </names>
  </desktops>
  <keyboard>
    <default />
    <keybind key="A-Tab">
      <action name="NextWindow" />
    </keybind>
    <keybind key="A-S-Tab">
      <action name="PreviousWindow" />
    </keybind>
    <keybind key="W-Return">
      <action name="Execute"><command>${LABWC_TERMINAL}</command></action>
    </keybind>
    <keybind key="W-t">
      <action name="Execute"><command>foot</command></action>
    </keybind>
    <keybind key="W-b">
      <action name="Execute"><command>thorium-browser</command></action>
    </keybind>
    <keybind key="W-d">
      <action name="Execute"><command>${LABWC_LAUNCHER_CMD}</command></action>
    </keybind>
    <keybind key="W-space">
      <action name="Execute"><command>${LABWC_LAUNCHER_CMD}</command></action>
    </keybind>
    <keybind key="W-e">
      <action name="Execute"><command>thunar</command></action>
    </keybind>
    <keybind key="W-f">
      <action name="Execute"><command>thunar</command></action>
    </keybind>
    <keybind key="W-1">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-workspace-state 1</command></action>
      <action name="GoToDesktop" to="1" />
    </keybind>
    <keybind key="W-2">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-workspace-state 2</command></action>
      <action name="GoToDesktop" to="2" />
    </keybind>
    <keybind key="W-3">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-workspace-state 3</command></action>
      <action name="GoToDesktop" to="3" />
    </keybind>
    <keybind key="W-4">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-workspace-state 4</command></action>
      <action name="GoToDesktop" to="4" />
    </keybind>
    <keybind key="W-S-1">
      <action name="SendToDesktop" to="1" follow="no" />
    </keybind>
    <keybind key="W-S-2">
      <action name="SendToDesktop" to="2" follow="no" />
    </keybind>
    <keybind key="W-S-3">
      <action name="SendToDesktop" to="3" follow="no" />
    </keybind>
    <keybind key="W-S-4">
      <action name="SendToDesktop" to="4" follow="no" />
    </keybind>
    <keybind key="W-q">
      <action name="Close" />
    </keybind>
    <keybind key="W-l">
      <action name="Execute"><command>swaylock -f</command></action>
    </keybind>
    <keybind key="Print">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-screenshot-full</command></action>
    </keybind>
    <keybind key="S-Print">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-screenshot-region</command></action>
    </keybind>
    <keybind key="W-S-r">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-record-toggle</command></action>
    </keybind>
    <keybind key="W-S-e">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-power-menu</command></action>
    </keybind>
  </keyboard>
</labwc_config>
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/labwc/rc.xml" "$rc_xml"
}

render_labwc_menu_xml() {
  local menu_xml
  menu_xml="$(cat <<'EOF'
<?xml version="1.0"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Applications">
    <item label="Terminal">
      <action name="Execute"><command>footclient</command></action>
    </item>
    <item label="Launcher">
      <action name="Execute"><command>wofi --show drun</command></action>
    </item>
    <item label="Files">
      <action name="Execute"><command>thunar</command></action>
    </item>
    <item label="NNN">
      <action name="Execute"><command>footclient -e nnn</command></action>
    </item>
    <item label="Audio">
      <action name="Execute"><command>pavucontrol</command></action>
    </item>
    <item label="Power">
      <action name="Execute"><command>/usr/local/bin/debian-labwc-power-menu</command></action>
    </item>
  </menu>
</openbox_menu>
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/labwc/menu.xml" "$menu_xml"
}

render_labwc_autostart() {
  local wallpaper_path
  local autostart
  wallpaper_path="$(primary_wallpaper_target_path)"
  autostart="$(cat <<EOF
#!/bin/sh
set -eu
IFS='
	'

export XDG_CURRENT_DESKTOP=labwc:wlroots

wait_for_session_bus() {
  bus_socket="\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}/bus"
  attempt=1
  while [ "\$attempt" -le 10 ]; do
    if [ -n "\${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "\$bus_socket" ]; then
      return 0
    fi
    sleep 1
    attempt=\$((attempt + 1))
  done
  return 1
}

update_activation_environment() {
  if [ "\${LABWC_UPDATE_ACTIVATION_ENV:-0}" != "1" ]; then
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user import-environment "\$@" >/dev/null 2>&1 || true
  fi
  if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd "\$@" >/dev/null 2>&1 || true
  fi
}

pgrep -x foot >/dev/null 2>&1 || foot --server &
pgrep -x swaybg >/dev/null 2>&1 || swaybg -i "$wallpaper_path" -m "${LABWC_WALLPAPER_MODE}" &

wait_for_session_bus || true
update_activation_environment \
  DISPLAY \
  WAYLAND_DISPLAY \
  XDG_CURRENT_DESKTOP \
  XDG_SESSION_TYPE \
  XDG_SESSION_DESKTOP \
  DESKTOP_SESSION \
  XCURSOR_THEME \
  XCURSOR_SIZE \
  GPG_TTY \
  SSH_AUTH_SOCK \
  PASSWORD_STORE \
  ELECTRON_OZONE_PLATFORM_HINT \
  QT_QPA_PLATFORM \
  QT_WAYLAND_DISABLE_WINDOWDECORATION

pgrep -x lxpolkit >/dev/null 2>&1 || lxpolkit &
/usr/local/bin/debian-labwc-workspace-state 1 >/dev/null 2>&1 || true
pgrep -x waybar >/dev/null 2>&1 || waybar &
pgrep -x kanshi >/dev/null 2>&1 || kanshi &
pgrep -x mako >/dev/null 2>&1 || mako &
if command -v /usr/local/bin/debian-labwc-unlock-gpg-key >/dev/null 2>&1; then
  (
    sleep 2
    /usr/local/bin/debian-labwc-unlock-gpg-key
  ) >/dev/null 2>&1 &
fi
pgrep -x swayidle >/dev/null 2>&1 || swayidle \
  timeout "${LABWC_IDLE_LOCK_SECONDS}" 'swaylock -f' \
  timeout "${LABWC_IDLE_DPMS_SECONDS}" '/usr/local/bin/debian-labwc-dpms off' \
  resume '/usr/local/bin/debian-labwc-dpms on' \
  before-sleep 'swaylock -f' &

if [ ! -f "$LABWC_TARGET_HOME/.config/debian-labwc/.outputs-refined" ]; then
  /usr/local/bin/debian-labwc-refresh-outputs >/dev/null 2>&1 &
fi

autostart_dir="$LABWC_TARGET_HOME/.config/labwc/autostart.d"
if [ -d "\$autostart_dir" ]; then
  find "\$autostart_dir" -maxdepth 1 -type f -name '*.sh' | sort | while IFS= read -r autostart_fragment; do
    [ -n "\$autostart_fragment" ] || continue
    "\$autostart_fragment" >/dev/null 2>&1 || true
  done
fi
EOF
)"
  render_user_script "$LABWC_TARGET_HOME/.config/labwc/autostart" "$autostart"
}

render_labwc_shutdown() {
  local shutdown
  shutdown="$(cat <<'EOF'
#!/bin/sh
set -eu
IFS='
	'

# Stop session clients first so they do not keep poking D-Bus or PipeWire
# while the compositor and user bus are already shutting down.
pkill -x "waybar" >/dev/null 2>&1 || true
pkill -x "kanshi" >/dev/null 2>&1 || true
pkill -x "mako" >/dev/null 2>&1 || true
pkill -x "lxpolkit" >/dev/null 2>&1 || true
pkill -x "swayidle" >/dev/null 2>&1 || true
pkill -x "crystal-dock" >/dev/null 2>&1 || true
pkill -x "nwg-dock" >/dev/null 2>&1 || true

if command -v gpgconf >/dev/null 2>&1; then
  gpgconf --kill gpg-agent >/dev/null 2>&1 || true
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user stop \
    xdg-desktop-portal.service \
    xdg-desktop-portal-wlr.service \
    wireplumber.service \
    pipewire-pulse.service \
    pipewire.service \
    pipewire-pulse.socket \
    pipewire.socket >/dev/null 2>&1 || true
fi
EOF
)"
  render_user_script "$LABWC_TARGET_HOME/.config/labwc/shutdown" "$shutdown"
}

render_gpg_agent_override() {
  render_user_file "$LABWC_TARGET_HOME/.config/systemd/user/gpg-agent.service.d/override.conf" $'[Service]\nTimeoutStopSec=10s\n'
}

render_portal_unit_overrides() {
  render_user_file "$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal.service.d/override.conf" $'[Unit]\nWants=pipewire.service wireplumber.service xdg-desktop-portal-wlr.service\nAfter=pipewire.service wireplumber.service xdg-desktop-portal-wlr.service\n'
  render_user_file "$LABWC_TARGET_HOME/.config/systemd/user/xdg-desktop-portal-wlr.service.d/override.conf" $'[Unit]\nWants=pipewire.service wireplumber.service\nAfter=pipewire.service wireplumber.service\nBindsTo=pipewire.service\n'
}

render_gpg_agent_config() {
  [[ "${KWALLET_SESSION_GPG_CACHE_TTL_SEC:-}" =~ ^[1-9][0-9]*$ ]] || die "KWALLET_SESSION_GPG_CACHE_TTL_SEC must be a positive integer, found '${KWALLET_SESSION_GPG_CACHE_TTL_SEC:-}'"
  render_user_private_file "$LABWC_TARGET_HOME/.gnupg/gpg-agent.conf" "enable-ssh-support
pinentry-program /usr/bin/pinentry-gtk-2
disable-scdaemon
default-cache-ttl ${KWALLET_SESSION_GPG_CACHE_TTL_SEC}
max-cache-ttl ${KWALLET_SESSION_GPG_CACHE_TTL_SEC}
default-cache-ttl-ssh ${KWALLET_SESSION_GPG_CACHE_TTL_SEC}
max-cache-ttl-ssh ${KWALLET_SESSION_GPG_CACHE_TTL_SEC}
"
}

render_waybar_config() {
  local waybar
  waybar="$(cat <<'EOF'
{
  "layer": "top",
  "position": "top",
  "height": 42,
  "spacing": 6,
  "modules-left": ["custom/launcher", "custom/workspace-1", "custom/workspace-2", "custom/workspace-3", "custom/workspace-4"],
  "modules-center": ["clock"],
  "modules-right": ["network", "pulseaudio", "battery", "backlight", "cpu", "memory", "disk", "custom/player", "tray", "custom/power"],
  "custom/launcher": {
    "format": "Menu",
    "tooltip": false,
    "on-click": "/usr/local/bin/debian-labwc-launcher-menu",
    "on-click-right": "wofi --show drun"
  },
  "custom/workspace-1": {
    "exec": "/usr/local/bin/debian-labwc-workspace-status 1",
    "return-type": "json",
    "interval": "once",
    "signal": 10,
    "tooltip": false,
    "on-click": "/usr/local/bin/debian-labwc-workspace-activate 1"
  },
  "custom/workspace-2": {
    "exec": "/usr/local/bin/debian-labwc-workspace-status 2",
    "return-type": "json",
    "interval": "once",
    "signal": 10,
    "tooltip": false,
    "on-click": "/usr/local/bin/debian-labwc-workspace-activate 2"
  },
  "custom/workspace-3": {
    "exec": "/usr/local/bin/debian-labwc-workspace-status 3",
    "return-type": "json",
    "interval": "once",
    "signal": 10,
    "tooltip": false,
    "on-click": "/usr/local/bin/debian-labwc-workspace-activate 3"
  },
  "custom/workspace-4": {
    "exec": "/usr/local/bin/debian-labwc-workspace-status 4",
    "return-type": "json",
    "interval": "once",
    "signal": 10,
    "tooltip": false,
    "on-click": "/usr/local/bin/debian-labwc-workspace-activate 4"
  },
  "clock": {
    "interval": 30,
    "format": "{:%a %b %d  %H:%M}",
    "format-alt": "{:%Y-%m-%d  %H:%M:%S}",
    "tooltip": true,
    "tooltip-format": "<tt><small>{calendar}</small></tt>",
    "calendar": {
      "mode": "month",
      "weeks-pos": "right",
      "on-scroll": 1,
      "format": {
        "months": "<span color='#f6bd60'><b>{}</b></span>",
        "weekdays": "<span color='#8ecae6'><b>{}</b></span>",
        "weeks": "<span color='#94d2bd'><b>W{}</b></span>",
        "today": "<span color='#ffb4a2'><b><u>{}</u></b></span>"
      }
    },
    "actions": {
      "on-click-right": "mode",
      "on-scroll-up": "shift_up",
      "on-scroll-down": "shift_down"
    },
    "on-click": "gsimplecal"
  },
  "tray": {
    "spacing": 8
  },
  "network": {
    "interval": 5,
    "family": "ipv4",
    "format-wifi": "WiFi  {essid}",
    "format-ethernet": "LAN  {ifname}",
    "format-linked": "LAN  {ifname} (no ip)",
    "format-disconnected": "Net  offline",
    "format-disabled": "Net  down",
    "tooltip-format-wifi": "{essid}\n{signalStrength}%  {ipaddr}\n↑ {bandwidthUpBytes}  ↓ {bandwidthDownBytes}",
    "tooltip-format-ethernet": "{ifname}\n{ipaddr}\n↑ {bandwidthUpBytes}  ↓ {bandwidthDownBytes}",
    "tooltip-format-disconnected": "Network disconnected",
    "on-click": "/usr/local/bin/debian-labwc-module-menu network quick",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu network menu"
  },
  "pulseaudio": {
    "format": "Vol  {volume}%",
    "format-muted": "Mute",
    "tooltip-format": "{desc}",
    "scroll-step": 5,
    "reverse-scrolling": true,
    "reverse-mouse-scrolling": true,
    "on-click": "pavucontrol",
    "on-click-middle": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu audio menu"
  },
  "battery": {
    "interval": 15,
    "states": {
      "warning": 30,
      "critical": 15
    },
    "format": "Bat  {capacity}%",
    "format-charging": "Charge  {capacity}%",
    "format-full": "Full  {capacity}%",
    "format-warning": "Low  {capacity}%",
    "format-critical": "Crit  {capacity}%",
    "tooltip-format": "{timeTo}\nHealth {health}%  Cycles {cycles}",
    "on-click": "/usr/local/bin/debian-labwc-module-menu battery menu",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu battery details"
  },
  "backlight": {
    "format": "Bright  {percent}%",
    "scroll-step": 5,
    "tooltip-format": "Brightness {percent}%",
    "reverse-scrolling": true,
    "reverse-mouse-scrolling": true,
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu brightness menu"
  },
  "cpu": {
    "interval": 5,
    "states": {
      "warning": 65,
      "critical": 85
    },
    "format": "CPU  {usage}%",
    "tooltip": true,
    "on-click": "/usr/local/bin/debian-labwc-module-menu system monitor",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu system menu"
  },
  "memory": {
    "interval": 10,
    "states": {
      "warning": 70,
      "critical": 90
    },
    "format": "RAM  {percentage}%",
    "tooltip-format": "{used:0.1f} GiB / {total:0.1f} GiB\nSwap {swapUsed:0.1f} / {swapTotal:0.1f} GiB",
    "on-click": "/usr/local/bin/debian-labwc-module-menu system monitor",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu system memory"
  },
  "disk": {
    "interval": 30,
    "path": "/",
    "unit": "GiB",
    "states": {
      "warning": 75,
      "critical": 90
    },
    "format": "Disk  {percentage_used}%",
    "tooltip-format": "{used} used of {total}\n{free} free on {path}",
    "on-click": "/usr/local/bin/debian-labwc-module-menu storage ncdu",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu storage menu"
  },
  "custom/player": {
    "exec": "/usr/local/bin/debian-labwc-player-status",
    "interval": 2,
    "return-type": "text",
    "max-length": 38,
    "tooltip": false,
    "on-click": "playerctl play-pause",
    "on-click-middle": "playerctl stop",
    "on-click-right": "/usr/local/bin/debian-labwc-module-menu player menu",
    "on-scroll-up": "playerctl next",
    "on-scroll-down": "playerctl previous"
  },
  "custom/power": {
    "format": "Power",
    "tooltip": false,
    "on-click": "/usr/local/bin/debian-labwc-power-menu"
  }
}
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/waybar/config.jsonc" "$waybar"
}

render_waybar_style() {
  local css
  css="$(cat <<'EOF'
* {
  font-family: "Noto Sans", "Font Awesome 6 Free", "Material Design Icons";
  font-size: 13px;
  min-height: 0;
  font-feature-settings: "tnum";
}

window#waybar {
  background: rgba(10, 14, 20, 0.84);
  color: #edf2f7;
  border-bottom: 1px solid rgba(173, 181, 189, 0.16);
}

#custom-launcher,
#custom-workspace-1,
#custom-workspace-2,
#custom-workspace-3,
#custom-workspace-4,
#clock,
#network,
#pulseaudio,
#battery,
#backlight,
#cpu,
#memory,
#disk,
#custom-player,
#custom-power,
#tray {
  margin: 5px 0 5px 8px;
  padding: 0 12px;
  min-height: 28px;
  border-radius: 14px;
  background: rgba(25, 32, 44, 0.74);
  border: 1px solid rgba(88, 101, 119, 0.25);
}

#custom-launcher {
  color: #f6bd60;
  font-weight: 600;
}

#custom-workspace-1,
#custom-workspace-2,
#custom-workspace-3,
#custom-workspace-4 {
  min-width: 18px;
  padding: 0 11px;
  color: #cbd5e1;
  font-weight: 600;
}

#custom-workspace-1.active,
#custom-workspace-2.active,
#custom-workspace-3.active,
#custom-workspace-4.active {
  background: rgba(246, 189, 96, 0.94);
  border-color: rgba(246, 189, 96, 0.6);
  color: #0f1720;
}

#clock {
  color: #f3f4f6;
}

#network.disconnected,
#network.disabled {
  color: #f6ad55;
}

#pulseaudio.muted {
  color: #f6ad55;
}

#battery.charging,
#battery.full {
  color: #9ae6b4;
}

#battery.warning,
#cpu.warning,
#memory.warning,
#disk.warning {
  color: #f6e05e;
}

#battery.critical,
#cpu.critical,
#memory.critical,
#disk.critical {
  color: #fc8181;
}

#custom-player {
  color: #c4b5fd;
}

#custom-power {
  background: rgba(68, 25, 33, 0.78);
  border-color: rgba(246, 173, 173, 0.28);
  color: #fed7d7;
  font-weight: 600;
}

#custom-launcher:hover,
#custom-workspace-1:hover,
#custom-workspace-2:hover,
#custom-workspace-3:hover,
#custom-workspace-4:hover,
#clock:hover,
#network:hover,
#pulseaudio:hover,
#battery:hover,
#backlight:hover,
#cpu:hover,
#memory:hover,
#disk:hover,
#custom-player:hover,
#custom-power:hover,
#tray:hover {
  background: rgba(40, 54, 74, 0.92);
  border-color: rgba(119, 141, 169, 0.38);
}

#custom-workspace-1.active:hover,
#custom-workspace-2.active:hover,
#custom-workspace-3.active:hover,
#custom-workspace-4.active:hover {
  background: rgba(246, 189, 96, 0.94);
  border-color: rgba(246, 189, 96, 0.6);
}
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/waybar/style.css" "$css"
}

kanshi_output_line() {
  local output_name="$1"
  local mode_name="$2"
  local hz="$3"
  local position="$4"
  local enabled_state="$5"
  local line

  line="  output \"$output_name\""
  if [[ -n "$mode_name" && -n "$hz" ]]; then
    line+=" mode ${mode_name}@${hz}Hz"
  fi
  if [[ -n "$position" ]]; then
    line+=" position ${position}"
  fi
  line+=" ${enabled_state}"
  printf '%s\n' "$line"
}

render_kanshi_config() {
  local internal_output="${LABWC_INTERNAL_OUTPUT:-}"
  local external_output="${LABWC_EXTERNAL_OUTPUT:-}"
  local internal_profile=""
  local external_clause=""

  if [[ -n "$internal_output" ]]; then
    local internal_line
    internal_line="$(kanshi_output_line "$internal_output" "${LABWC_INTERNAL_MODE}" "${LABWC_INTERNAL_HZ}" "0,0" "enable")"
    internal_profile="$(cat <<EOF
profile internal {
${internal_line}
}
EOF
)"
  fi

  if [[ -n "$external_output" ]]; then
    if [[ -n "$internal_output" ]]; then
      local external_line dual_external_line dual_internal_line
      external_line="$(kanshi_output_line "$external_output" "${LABWC_EXTERNAL_MODE}" "${LABWC_EXTERNAL_HZ}" "0,0" "enable")"
      dual_external_line="$(kanshi_output_line "$external_output" "${LABWC_EXTERNAL_MODE}" "${LABWC_EXTERNAL_HZ}" "0,0" "enable")"
      dual_internal_line="$(kanshi_output_line "$internal_output" "${LABWC_INTERNAL_MODE}" "${LABWC_INTERNAL_HZ}" "1920,0" "enable")"
      external_clause="$(cat <<EOF
profile external {
${external_line}
  output "$internal_output" disable
}

profile dual {
${dual_external_line}
${dual_internal_line}
}
EOF
)"
    else
      local external_only_line
      external_only_line="$(kanshi_output_line "$external_output" "${LABWC_EXTERNAL_MODE}" "${LABWC_EXTERNAL_HZ}" "0,0" "enable")"
      external_clause="$(cat <<EOF
profile external {
${external_only_line}
}
EOF
)"
    fi
  fi

  local config
  config="$(cat <<EOF
$internal_profile
$external_clause
EOF
)"
  render_user_file "$LABWC_TARGET_HOME/.config/kanshi/config" "$config"
}

render_wofi() {
  render_user_file "$LABWC_TARGET_HOME/.config/wofi/config" $'show=drun\nwidth=720\nheight=540\nprompt=Run\nallow_images=true\ninsensitive=true\ngtk_dark=true\n'
  render_user_file "$LABWC_TARGET_HOME/.config/wofi/style.css" $'window {\n  margin: 0;\n  padding: 14px;\n  border: 1px solid rgba(111, 124, 143, 0.32);\n  border-radius: 18px;\n  background-color: rgba(12, 17, 24, 0.96);\n}\n#outer-box {\n  padding: 4px;\n}\n#input {\n  margin: 0 0 12px 0;\n  padding: 12px 14px;\n  border-radius: 12px;\n  border: 1px solid rgba(80, 97, 119, 0.35);\n  background-color: rgba(24, 31, 43, 0.92);\n  color: #edf2f7;\n}\n#entry {\n  padding: 10px 12px;\n  border-radius: 12px;\n}\n#entry:selected {\n  background: linear-gradient(180deg, rgba(109, 196, 237, 0.92), rgba(71, 167, 214, 0.92));\n  color: #07111b;\n}\n#text {\n  color: inherit;\n}\n'
}

render_mako() {
  render_user_file "$LABWC_TARGET_HOME/.config/mako/config" $'font=Noto Sans 11\nbackground-color=#111827f2\ntext-color=#e5e7ebff\nwidth=420\nheight=220\nouter-margin=14,14,0,14\nmargin=8\npadding=12,14\nborder-size=2\nborder-color=#6dc4edff\nborder-radius=14\nprogress-color=over #f6bd60ff\nicons=1\nmax-icon-size=48\nicon-path=/usr/share/icons/Papirus-Dark:/usr/share/icons/Papirus:/usr/share/icons/Adwaita:/usr/share/icons/hicolor\nicon-border-radius=8\nmarkup=1\nactions=1\nhistory=1\nmax-history=100\nsort=-time\ngroup-by=summary,app-name,urgency\nformat=<b>%s</b>\\n%b\nhidden-format=<b>%h hidden</b> (%t total)\ndefault-timeout=8000\nignore-timeout=0\nmax-visible=6\nlayer=overlay\nanchor=top-right\non-button-left=invoke-default-action\non-button-middle=dismiss --no-history\non-button-right=dismiss\non-touch=dismiss\n\n[grouped]\nformat=<b>%s</b>\\n%b\\n<small>%g notifications</small>\n\n[hidden]\nborder-color=#94a3b8ff\nprogress-color=over #94a3b8ff\n\n[actionable]\nborder-color=#94d2bdff\n\n[urgency=low]\nbackground-color=#0f1720f2\nborder-color=#64748bff\ndefault-timeout=5000\n\n[urgency=normal]\nbackground-color=#111827f2\nborder-color=#6dc4edff\ndefault-timeout=8000\n\n[urgency=critical]\nbackground-color=#2b1116f2\ntext-color=#fff1f2ff\nborder-color=#ef4444ff\nprogress-color=over #ef4444ff\ndefault-timeout=0\n\n[mode=do-not-disturb]\ninvisible=1\n'
}

render_swaylock() {
  local wallpaper_path
  wallpaper_path="$(primary_wallpaper_target_path)"
  render_user_file "$LABWC_TARGET_HOME/.config/swaylock/config" "daemonize
clock
font=Noto Sans
indicator
image=${wallpaper_path}
scaling=${LABWC_WALLPAPER_MODE}
color=111111
inside-color=202020
ring-color=4a89dc
line-color=111111
key-hl-color=88c0d0
"
}

render_foot() {
  render_user_file "$LABWC_TARGET_HOME/.config/foot/foot.ini" $'[main]\nfont=Noto Sans Mono:size=11\npad=8x8\n\n[bell]\nsystem=no\n\n[colors]\nbackground=111111\nforeground=f5f5f5\n'
}

render_gammastep() {
  render_user_file "$LABWC_TARGET_HOME/.config/gammastep/config" $'[general]\nadjustment-method=wayland\n[manual]\nlat=0.0\nlon=0.0\n'
}

render_portals() {
  render_user_file "$LABWC_TARGET_HOME/.config/xdg-desktop-portal/portals.conf" $'[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.ScreenCast=wlr\norg.freedesktop.impl.portal.Screenshot=wlr\norg.freedesktop.impl.portal.FileChooser=gtk\n'
}

install_wallpaper() {
  local wallpaper_source_path wallpaper_name
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.local/share/debian-labwc"
  while IFS= read -r wallpaper_source_path; do
    [[ -n "$wallpaper_source_path" ]] || continue
    wallpaper_name="$(basename "$wallpaper_source_path")"
    run_cmd install -m 0644 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$wallpaper_source_path" "$LABWC_TARGET_HOME/.local/share/debian-labwc/$wallpaper_name"
  done < <(find "$SCRIPT_DIR/wallpaper" -maxdepth 1 -type f | sort)
  require_file "$(primary_wallpaper_target_path)"
}

render_all_configs() {
  local config_root="$LABWC_TARGET_HOME/.config"
  ensure_user_base_dirs
  run_cmd install -d -m 0755 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" \
    "$config_root/labwc" \
    "$config_root/waybar" \
    "$config_root/kanshi" \
    "$config_root/xfce4" \
    "$config_root/wofi" \
    "$config_root/mako" \
    "$config_root/fzf" \
    "$config_root/swaylock" \
    "$config_root/foot" \
    "$config_root/gammastep" \
    "$config_root/xdg-desktop-portal" \
    "$config_root/debian-labwc" \
    "$config_root/systemd/user/gpg-agent.service.d" \
    "$config_root/systemd/user/xdg-desktop-portal.service.d" \
    "$config_root/systemd/user/xdg-desktop-portal-wlr.service.d" \
    "$config_root/systemd/user" \
    "$config_root"
  run_cmd install -d -m 0700 -o "$LABWC_TARGET_USER" -g "$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.gnupg"

  render_home_dirs
  render_shell_startup_files
  render_xfce_helpers
  render_tmux_config
  render_fzf_config
  install_wallpaper
  render_labwc_environment
  render_labwc_rc_xml
  render_labwc_menu_xml
  render_labwc_autostart
  render_labwc_shutdown
  render_gpg_agent_override
  render_gpg_agent_config
  render_portal_unit_overrides
  render_waybar_config
  render_waybar_style
  render_kanshi_config
  render_wofi
  render_mako
  render_swaylock
  render_foot
  render_gammastep
  render_portals
  run_cmd chown -R "$LABWC_TARGET_USER:$LABWC_TARGET_USER" "$LABWC_TARGET_HOME/.config" "$LABWC_TARGET_HOME/.local"
}
