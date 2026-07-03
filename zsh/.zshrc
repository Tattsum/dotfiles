#!/usr/bin/env zsh

# Kiro CLI pre block. Keep at the top of this file.
[[ -f "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh" ]] && builtin source "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh"

autoload -Uz compinit colors
compinit
colors

export LANG=ja_JP.UTF-8
export EDITOR=vim

# 履歴設定（機密コマンドを残さないように調整推奨）
HISTFILE=$HOME/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt hist_reduce_blanks
setopt inc_append_history
setopt share_history

# 基本オプション
setopt no_beep
setopt interactive_comments
setopt extended_glob

# 補完の細かい設定
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' ignore-parents parent pwd ..
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin

# プロンプトは starship に委譲する（git 表示も starship 側で行うため
# zsh の vcs_info は使わない）。

# よく使うエイリアス
alias ..='cd ..'
alias mkdir='mkdir -p'
alias relogin='exec $SHELL -l'
alias f='open .'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# モダン CLI への置き換え（インストールされている場合のみ）
command -v bat   >/dev/null 2>&1 && alias cat='bat'
command -v procs >/dev/null 2>&1 && alias top='procs' && alias ps='procs'
command -v dust  >/dev/null 2>&1 && alias du='dust'
command -v fd    >/dev/null 2>&1 && alias find='fd'
command -v sd    >/dev/null 2>&1 && alias sed='sd'

# グローバルエイリアス
alias -g L='| less'
alias -g G='| grep'

# PATH やツールの初期化はここに追記
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:$HOME/go/bin:$PATH"

# Go プロジェクトのパス（`cd $atami` のように移動先として使う）
export fastmedia="$HOME/go/src/github.com/fastmedia"
export atami="$fastmedia/atami"
export kurobe="$fastmedia/kurobe"
export cms="$fastmedia/cms"
export nginx="$fastmedia/nginx"
export protobuf="$fastmedia/protobuf"
export hakone="$fastmedia/hakone"
export batch="$fastmedia/batch"
export beppu="$fastmedia/beppu"
export shirahama="$fastmedia/shirahama"
export tattsum="$HOME/go/src/github.com/Tattsum"
export haul="$HOME/go/src/github.com/haul-inc"

# 作業用ディレクトリ
export KUROBE_DIR="$HOME/kurobe-data"

# プロンプト（starship）を初期化
eval "$(starship init zsh)"

# ツールの初期化（インストールされている場合のみ。未導入マシンでもエラーにしない）
command -v rbenv  >/dev/null 2>&1 && eval "$(rbenv init - zsh)"
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v mcfly  >/dev/null 2>&1 && eval "$(mcfly init zsh)"   # 履歴検索（Ctrl-R）

# pyenv
if command -v pyenv >/dev/null 2>&1; then
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/shims:$PATH"
  eval "$(pyenv init - zsh)"
fi

# nodebrew
[[ -d "$HOME/.nodebrew/current/bin" ]] && export PATH="$HOME/.nodebrew/current/bin:$PATH"

# nvm
export NVM_DIR="$HOME/.nvm"
[[ -s "/opt/homebrew/opt/nvm/nvm.sh" ]] && source "/opt/homebrew/opt/nvm/nvm.sh"

# mise（node/java 等のバージョン管理。.mise.toml のあるプロジェクトでは
# nodebrew/nvm より優先させるため、それらの後で activate する）
command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"

# Google Cloud SDK（Homebrew Cask 版の path/補完。formula 版は PATH に既に入っている）
[[ -f '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc' ]] \
  && source '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'
[[ -f '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc' ]] \
  && source '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'

# hstr（履歴検索。Ctrl-R は mcfly が使うため hh で起動する）
if command -v hstr >/dev/null 2>&1; then
  alias hh='hstr'
  export HSTR_CONFIG=hicolor
  setopt hist_ignore_space
fi

# ローカル専用の機密設定は ~/.zshrc.local に切り出す
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi

# peco で ~/.ssh/conf.d/*-dev.config の接続先を選んで ssh する
alias sshp='grep Match ~/.ssh/conf.d/*-dev.config | awk '\''{print $3, $7}'\'' | peco | awk '\''{print $1}'\'' | xargs -o -n 1 ssh'

# Kiro CLI post block. Keep at the bottom of this file.
[[ -f "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.post.zsh" ]] && builtin source "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.post.zsh"

