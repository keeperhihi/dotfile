#!/usr/bin/env zsh

# 为本仓库会覆盖的目标创建可校验快照。

emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077

die() {
  print -u2 -- "错误：$*"
  exit 1
}

is_safe_relative_target() {
  local value="$1"
  [[ -n "$value" && "$value" != "." && "$value" != ".." && "$value" != /* \
    && "$value" != ../* && "$value" != */../* && "$value" != */.. ]]
}

[[ -n "${HOME:-}" && "$HOME" == /* && "$HOME" != "/" ]] || die "HOME 目录无效"
command -v tar >/dev/null 2>&1 || die "缺少 tar 命令"

typeset -r script_dir="${0:A:h}"
typeset -r targets_file="$script_dir/managed-targets.zsh"
[[ -r "$targets_file" ]] || die "缺少受管目标清单：$targets_file"
source "$targets_file"
(( ${#DOTFILES_MANAGED_TARGETS[@]} > 0 )) || die "受管目标清单为空"

# 先转成绝对路径，再交给 BSD/GNU 工具，避免依赖并非所有 macOS 工具都接受的 `--`。
typeset -r backup_dir="${${DOTFILES_BACKUP_DIR:-$HOME/.local/state/dotfiles-backups}:A}"
typeset -r timestamp="$(date +%Y%m%d-%H%M%S)"
typeset -r backup_name="dotfiles-${timestamp}.tar.gz"
typeset -r backup_file="$backup_dir/$backup_name"
typeset -r checksum_file="${backup_file}.sha256"

typeset -a existing_targets=()
typeset relative_path target_path

for relative_path in "${DOTFILES_MANAGED_TARGETS[@]}"; do
  is_safe_relative_target "$relative_path" || die "受管目标不安全：$relative_path"
  target_path="$HOME/$relative_path"

  if [[ "$backup_file" == "$target_path" || "$backup_file" == "$target_path/"* ]]; then
    die "备份目录不能位于受管目标内：$backup_dir"
  fi

  # -L 同时识别目标不存在的失效符号链接。
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    existing_targets+=("$relative_path")
  fi
done

command mkdir -p "$backup_dir"
[[ ! -e "$backup_file" && ! -e "$checksum_file" ]] || die "同名备份已经存在：$backup_file"

if (( ${#existing_targets[@]} > 0 )); then
  command tar -C "$HOME" -czf "$backup_file" "${existing_targets[@]}"
else
  # 空快照也有意义：恢复时会删除 apply 新创建的全部受管目标。
  command tar -C "$HOME" -czf "$backup_file" -T /dev/null
fi

# 校验文件只记录归档文件名，整个备份目录移动后仍可验证。
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
  command rm -f "$backup_file"
  die "缺少 sha256sum 或 shasum，已删除无法校验的备份"
fi

command chmod 600 "$backup_file" "$checksum_file"

print -- "备份完成：$backup_file"
print -- "校验文件：$checksum_file"
