#!/usr/bin/env zsh

# 创建同时包含 HOME 有效目标与仓库 private 源码的新格式快照。

emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077

typeset script_file="${${(%):-%x}:A}"
typeset script_dir="${script_file:h}"
typeset script_name="${script_file:t}"
typeset home_arg="${HOME:-}"
typeset source_arg="${DOTFILES_SOURCE_DIR:-${script_dir:h}}"
typeset platform_arg="${DOTFILES_PLATFORM:-}"
typeset backup_dir_arg="${DOTFILES_BACKUP_DIR:-}"

usage() {
  print -u2 -- "用法：$script_name [选项]"
  print -u2 -- "  --home PATH             覆盖目标 HOME"
  print -u2 -- "  --source PATH           覆盖仓库源码目录"
  print -u2 -- "  --platform darwin|linux 覆盖平台检测"
  print -u2 -- "  --output-dir PATH       覆盖备份目录"
  print -u2 -- "  --help                  显示帮助"
  exit 2
}

while (( $# > 0 )); do
  case "$1" in
    --home)
      (( $# >= 2 )) || usage
      home_arg="$2"
      shift
      ;;
    --source)
      (( $# >= 2 )) || usage
      source_arg="$2"
      shift
      ;;
    --platform)
      (( $# >= 2 )) || usage
      platform_arg="$2"
      shift
      ;;
    --output-dir)
      (( $# >= 2 )) || usage
      backup_dir_arg="$2"
      shift
      ;;
    --help|-h) usage ;;
    *) print -u2 -- "错误：未知选项：$1"; usage ;;
  esac
  shift
done

source "$script_dir/dotfiles-common.zsh"

dotfiles_require_absolute_directory HOME "$home_arg"
home_arg="${home_arg:A}"
[[ -n "$source_arg" && "$source_arg" == /* && "$source_arg" != "/" ]] \
  || dotfiles_die "源码目录无效：$source_arg"
[[ -d "$source_arg" && ! -L "$source_arg" ]] \
  || dotfiles_die "源码目录不存在或是符号链接：$source_arg"
source_arg="${source_arg:A}"

export DOTFILES_SOURCE_DIR="$source_arg"
export DOTFILES_SCRIPT_DIR="$script_dir"
export DOTFILES_PLATFORM="$platform_arg"
platform_arg="$(dotfiles_detect_platform)"
source "$script_dir/managed-targets.zsh"
dotfiles_load_targets "$platform_arg"

typeset private_dir="$source_arg/private"
dotfiles_normalize_private_permissions "$private_dir"

if [[ -z "$backup_dir_arg" ]]; then
  backup_dir_arg="$home_arg/.local/state/dotfiles-backups"
fi
[[ "$backup_dir_arg" == /* && "$backup_dir_arg" != "/" ]] \
  || dotfiles_die "备份目录必须是绝对路径：$backup_dir_arg"
typeset backup_dir="${backup_dir_arg:A}"
[[ "$backup_dir" != "$source_arg" && "$backup_dir" != "$source_arg/"* ]] \
  || dotfiles_die "备份目录不能位于仓库源码内：$backup_dir"
[[ "$backup_dir" != "$private_dir" && "$backup_dir" != "$private_dir/"* ]] \
  || dotfiles_die "备份目录不能位于 private 内：$backup_dir"

typeset ancestor="$backup_dir"
while [[ "$ancestor" != "/" ]]; do
  [[ ! -L "$ancestor" ]] \
    || dotfiles_die "备份目录路径包含符号链接：$ancestor"
  ancestor="${ancestor:h}"
done

command -v tar >/dev/null 2>&1 || dotfiles_die "缺少 tar 命令"
command -v mktemp >/dev/null 2>&1 || dotfiles_die "缺少 mktemp 命令"
command -v date >/dev/null 2>&1 || dotfiles_die "缺少 date 命令"

typeset timestamp="$(command date +%Y%m%d-%H%M%S)"
typeset backup_name="dotfiles-${timestamp}.tar.gz"
typeset backup_file="$backup_dir/$backup_name"
typeset checksum_file="${backup_file}.sha256"
typeset relative_path target_path
for relative_path in "${DOTFILES_MANAGED_TARGETS[@]}"; do
  dotfiles_is_safe_relative_path "$relative_path" \
    || dotfiles_die "受管目标不安全：$relative_path"
  target_path="$home_arg/$relative_path"
  dotfiles_validate_parent_chain "$target_path" "$home_arg"
  if [[ "$backup_file" == "$target_path" || "$backup_file" == "$target_path/"* \
     || "$checksum_file" == "$target_path" || "$checksum_file" == "$target_path/"* ]]; then
    dotfiles_die "备份文件位于受管目标内：$backup_file"
  fi
done
command mkdir -p "$backup_dir" \
  || dotfiles_die "无法创建备份目录：$backup_dir"
[[ ! -e "$backup_file" && ! -L "$backup_file" \
   && ! -e "$checksum_file" && ! -L "$checksum_file" ]] \
  || dotfiles_die "同名备份已经存在：$backup_file"

typeset staging_dir=""
typeset -i backup_committed=0
cleanup() {
  [[ -z "${staging_dir:-}" || ! -d "$staging_dir" ]] || command rm -rf "$staging_dir"
  if (( ! backup_committed )); then
    [[ ! -e "${backup_file:-}" && ! -L "${backup_file:-}" ]] || command rm -f "$backup_file"
    [[ ! -e "${checksum_file:-}" && ! -L "${checksum_file:-}" ]] || command rm -f "$checksum_file"
  fi
}
trap cleanup EXIT HUP INT TERM

staging_dir="$(command mktemp -d "${TMPDIR:-/tmp}/dotfiles-backup.XXXXXX")" \
  || dotfiles_die "无法创建备份临时目录"
command mkdir -p "$staging_dir/home" "$staging_dir/private"
command chmod 700 "$staging_dir" "$staging_dir/home" "$staging_dir/private"

# private 不存在时仍保留空的 private/ 前缀，保证恢复接口固定且可判定。
if [[ -e "$private_dir" || -L "$private_dir" ]]; then
  dotfiles_normalize_private_permissions "$private_dir"
  command tar -C "$source_arg" -cpf - private \
    | command tar -C "$staging_dir" -xpf -
fi
dotfiles_normalize_private_permissions "$staging_dir/private"

# HOME 目标逐项复制；只有 registry 的 backup=1 目标进入归档。
for relative_path in "${DOTFILES_BACKUP_TARGETS[@]}"; do
  target_path="$home_arg/$relative_path"
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    if [[ -d "$target_path" && ! -L "$target_path" ]]; then
      dotfiles_die "受管 HOME 目标是目录，无法生成文件目标备份：$relative_path"
    fi
    if [[ ! -L "$target_path" ]] && dotfiles_is_special_file "$target_path"; then
      dotfiles_die "受管 HOME 目标是特殊文件：$relative_path"
    fi
    command tar -C "$home_arg" -cpf - "$relative_path" \
      | command tar -C "$staging_dir/home" -xpf -
  fi
done

# 归档固定使用 home/ 与 private/ 前缀，避免 HOME 文件与源码混淆。
command tar -C "$staging_dir" -czf "$backup_file" home private \
  || dotfiles_die "无法创建备份归档：$backup_file"

if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$backup_dir"
    command sha256sum "$backup_name" > "${backup_name}.sha256"
  )
elif command -v shasum >/dev/null 2>&1; then
  (
    cd "$backup_dir"
    command shasum -a 256 "$backup_name" > "${backup_name}.sha256"
  )
else
  dotfiles_die "缺少 sha256sum 或 shasum，无法生成可校验备份"
fi

command chmod 600 "$backup_file" "$checksum_file"
backup_committed=1
print -- "备份完成：$backup_file"
print -- "校验文件：$checksum_file"
print -- "归档前缀：home/（HOME 目标）、private/（仓库私有源码）"
