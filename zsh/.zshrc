#!/usr/bin/env zsh

# Kiro CLI pre block. Keep at the top of this file.
[[ -f "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh" ]] && builtin source "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh"

autoload -Uz compinit colors vcs_info add-zsh-hook
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

# vcs_info を RPROMPT に表示
zstyle ':vcs_info:*' formats '%F{green}(%s)-[%b]%f'
zstyle ':vcs_info:*' actionformats '%F{red}(%s)-[%b|%a]%f'
function _update_vcs_info_msg() {
  LANG=en_US.UTF-8 vcs_info
  RPROMPT="${vcs_info_msg_0_}"
}
add-zsh-hook precmd _update_vcs_info_msg

# よく使うエイリアス
alias ..='cd ..'
alias mkdir='mkdir -p'
alias relogin='exec $SHELL -l'
alias f='open .'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# グローバルエイリアス
alias -g L='| less'
alias -g G='| grep'

# PATH やツールの初期化はここに追記
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:$PATH"

# 例：必要なら有効化
# eval "$(rbenv init -)"
# eval "$(direnv hook zsh)"
# eval "$(starship init zsh)"
# eval "$(zoxide init zsh)"

# ローカル専用の機密設定は ~/.zshrc.local に切り出す
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi

# Kiro CLI post block. Keep at the bottom of this file.
[[ -f "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.post.zsh" ]] && builtin source "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.post.zsh"

