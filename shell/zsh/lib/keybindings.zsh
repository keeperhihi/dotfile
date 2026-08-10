# ==============================================================================
# 编辑模式与历史搜索
# ==============================================================================

bindkey -e
WORDCHARS=${WORDCHARS//[\/]}

if (( $+functions[history-substring-search-up] )); then
  zmodload -F zsh/terminfo +p:terminfo

  typeset _dotfiles_key
  for _dotfiles_key in '^[[A' '^P' "${terminfo[kcuu1]}"; do
    [[ -n "$_dotfiles_key" ]] && bindkey "$_dotfiles_key" history-substring-search-up
  done
  for _dotfiles_key in '^[[B' '^N' "${terminfo[kcud1]}"; do
    [[ -n "$_dotfiles_key" ]] && bindkey "$_dotfiles_key" history-substring-search-down
  done
  bindkey -M vicmd 'k' history-substring-search-up
  bindkey -M vicmd 'j' history-substring-search-down
  unset _dotfiles_key
fi
