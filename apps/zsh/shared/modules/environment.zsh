# ==============================================================================
# 共享环境：profile 与交互式 shell 都可以安全重复加载
# ==============================================================================

typeset -g ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
typeset -g ZSH_COMPLETION_DIR="$ZSH_CACHE_DIR/completions"
typeset -gU path PATH fpath

typeset -a _dotfiles_user_bin_dirs
typeset _dotfiles_bin_dir
for _dotfiles_bin_dir in "$HOME/.local/bin" "$HOME/bin"; do
  [[ -d "$_dotfiles_bin_dir" ]] && _dotfiles_user_bin_dirs+=("$_dotfiles_bin_dir")
done
path=("${_dotfiles_user_bin_dirs[@]}" $path)

[[ -d "$ZSH_CACHE_DIR" ]] || command mkdir -p "$ZSH_CACHE_DIR"
[[ -d "$ZSH_COMPLETION_DIR" ]] || command mkdir -p "$ZSH_COMPLETION_DIR"
fpath=("$ZSH_COMPLETION_DIR" $fpath)

unset _dotfiles_bin_dir _dotfiles_user_bin_dirs
