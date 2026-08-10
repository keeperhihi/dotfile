# backup-dotfiles.zsh 与 restore-dotfiles.zsh 共用的受管目标清单。
# 只列 chezmoi 会创建或覆盖的持久配置；Zim/cache/history 等运行时状态不在这里。

typeset -ga DOTFILES_MANAGED_TARGETS=(
  .zshrc
  .zprofile
  .zimrc
  .config/chezmoi/chezmoi.toml
)
