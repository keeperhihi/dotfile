# ==============================================================================
# 个人 functions
# ==============================================================================

function tgz() {
  local path="${2%/}"
  command tar -czf "$1.tar.gz" -C "${path:h}" "${path:t}"
}

function untgz() {
  command mkdir -p "${2:-.}" && command tar -xzf "$1" -C "${2:-.}"
}

function awake() {
  sudo /usr/bin/pmset disablesleep 1
}

function slp() {
  sudo /usr/bin/pmset disablesleep 0 && sudo /usr/bin/pmset sleepnow
}
