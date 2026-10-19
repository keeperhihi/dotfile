# macOS 专属 alias 与函数。

function cb() {
  if (( $# == 0 )); then
    print -u2 -- "用法：cb <文件> 或 cb <命令> [参数...]"
    return 2
  fi
  if (( $# == 1 )) && [[ -e "$1" ]]; then
    if [[ ! -f "$1" || ! -r "$1" ]]; then
      print -u2 -- "cb：文件不可读：$1"
      return 1
    fi

    command pbcopy < "$1"
    return
  fi

  local output_file
  output_file="$(command mktemp "${TMPDIR:-/tmp}/cb.XXXXXX")" || return
  {
    "$@" >| "$output_file" || return
    command pbcopy < "$output_file"
  } always {
    command rm -f "$output_file"
  }
}

if (( $+commands[pmset] )); then
  alias zzz='pmset displaysleepnow'

  function awake() {
    sudo /usr/bin/pmset disablesleep 1
  }

  function slp() {
    sudo /usr/bin/pmset disablesleep 0 && sudo /usr/bin/pmset sleepnow
  }
fi
