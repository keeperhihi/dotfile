# macOS 专属 alias 与 sleep 管理函数。

if (( $+commands[pmset] )); then
  alias zzz='pmset displaysleepnow'

  function awake() {
    sudo /usr/bin/pmset disablesleep 1
  }

  function slp() {
    sudo /usr/bin/pmset disablesleep 0 && sudo /usr/bin/pmset sleepnow
  }
fi
