# Zim 框架适配器。

typeset -g ZIM_HOME="$HOME/.zim"
typeset -g ZIM_CONFIG_FILE="$HOME/.zimrc"
typeset -g ZSH_AUTOSUGGEST_MANUAL_REBIND=1
typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
zstyle ':zim:completion' dumpfile "$ZSH_CACHE_DIR/.zcompdump"

if [[ ! -s "$ZIM_HOME/zimfw.zsh" ]]; then
  command mkdir -p "$ZIM_HOME"
  if (( $+commands[curl] )); then
    if ! command curl -fsSL \
      -o "$ZIM_HOME/zimfw.zsh" \
      "https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh"; then
      command rm -f "$ZIM_HOME/zimfw.zsh"
      print -u2 -- "[dotfiles] Zim 下载失败"
    fi
  elif (( $+commands[wget] )); then
    if ! command wget -q \
      -O "$ZIM_HOME/zimfw.zsh" \
      "https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh"; then
      command rm -f "$ZIM_HOME/zimfw.zsh"
      print -u2 -- "[dotfiles] Zim 下载失败"
    fi
  else
    print -u2 -- "[dotfiles] 缺少 curl/wget，无法安装 Zim"
  fi
fi

if [[ -s "$ZIM_HOME/zimfw.zsh" ]]; then
  if [[ ! -r "$ZIM_HOME/init.zsh" || "$ZIM_HOME/init.zsh" -ot "$ZIM_CONFIG_FILE" ]]; then
    source "$ZIM_HOME/zimfw.zsh" init -q
  fi
  [[ -r "$ZIM_HOME/init.zsh" ]] && source "$ZIM_HOME/init.zsh"
else
  print -u2 -- "[dotfiles] Zim 尚未安装，跳过第三方模块"
fi
