# ==============================================================================
# 共享 functions
# ==============================================================================

function tgz() {
  local target_path="${2%/}"
  command tar -czf "$1.tar.gz" -C "${target_path:h}" "${target_path:t}"
}

function untgz() {
  command mkdir -p "${2:-.}" && command tar -xzf "$1" -C "${2:-.}"
}
