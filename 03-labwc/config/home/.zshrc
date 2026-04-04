# Managed by labwc
[[ -o interactive ]] || return 0

HISTSIZE=10000
SAVEHIST=20000
export CLICOLOR=1
export LS_COLORS='di=1;38;2;125;211;252:ln=1;38;2;109;196;237:so=38;2;148;210;189:pi=38;2;246;189;96:ex=1;38;2;148;210;189:bd=1;38;2;255;180;162:cd=1;38;2;255;180;162:su=37;41:sg=30;43:tw=30;42:ow=30;43:*.tar=38;2;196;181;253:*.tgz=38;2;196;181;253:*.gz=38;2;196;181;253:*.zip=38;2;196;181;253:*.xz=38;2;196;181;253:*.zst=38;2;196;181;253:*.bz2=38;2;196;181;253:*.7z=38;2;196;181;253:*.jpg=38;2;246;189;96:*.jpeg=38;2;246;189;96:*.png=38;2;246;189;96:*.gif=38;2;246;189;96:*.webp=38;2;246;189;96:*.svg=38;2;246;189;96:*.mp3=38;2;196;181;253:*.flac=38;2;196;181;253:*.wav=38;2;196;181;253:*.mp4=38;2;196;181;253:*.mkv=38;2;196;181;253:*.mov=38;2;196;181;253'

alias ls='ls --color=auto --group-directories-first'
alias ll='ls --color=auto --group-directories-first -alFh'
alias la='ls --color=auto --group-directories-first -A'

zcompdump_path="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-${ZSH_VERSION}"
mkdir -p "${zcompdump_path%/*}"
autoload -Uz compinit
compinit -d "$zcompdump_path"

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

if [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
