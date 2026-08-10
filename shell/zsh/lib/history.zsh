# ==============================================================================
# 命令历史
# ==============================================================================

HISTFILE="$HOME/.zhistory"
HISTSIZE=20000
SAVEHIST=10000

setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
