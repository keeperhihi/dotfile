#!/usr/bin/env zsh

# 从 backup-dotfiles.zsh 创建的快照恢复配置。
# 为准确恢复“原本不存在”的路径，写回快照前会删除当前受管目标。

emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

die() {
  print -u2 -- "错误：$*"
  exit 1
}

usage() {
  print -u2 -- "用法：${0:t} [--yes] <dotfiles-YYYYMMDD-HHMMSS.tar.gz>"
  print -u2 -- "  --yes  跳过交互确认；它是本脚本参数，不会传给 macOS 外部命令"
  exit 2
}

is_safe_relative_target() {
  local value="$1"
  [[ -n "$value" && "$value" != "." && "$value" != ".." && "$value" != /* \
    && "$value" != ../* && "$value" != */../* && "$value" != */.. ]]
}

is_managed_archive_entry() {
  local entry="$1"
  local target

  [[ -n "$entry" && "$entry" != /* \
    && "$entry" != ".." && "$entry" != ../* \
    && "$entry" != */../* && "$entry" != */.. ]] || return 1

  for target in "${DOTFILES_MANAGED_TARGETS[@]}"; do
    if [[ "$entry" == "$target" || "$entry" == "$target/"* ]]; then
      return 0
    fi
  done
  return 1
}

[[ -n "${HOME:-}" && "$HOME" == /* && "$HOME" != "/" ]] || die "HOME 目录无效"
command -v tar >/dev/null 2>&1 || die "缺少 tar 命令"
command -v mktemp >/dev/null 2>&1 || die "缺少 mktemp 命令"

typeset -r script_dir="${0:A:h}"
typeset -r targets_file="$script_dir/managed-targets.zsh"
[[ -r "$targets_file" ]] || die "缺少受管目标清单：$targets_file"
source "$targets_file"
(( ${#DOTFILES_MANAGED_TARGETS[@]} > 0 )) || die "受管目标清单为空"

typeset -i auto_confirm=0
if [[ "${1:-}" == "--yes" ]]; then
  auto_confirm=1
  shift
fi
(( $# == 1 )) || usage

typeset -r backup_file="${1:A}"
typeset -r checksum_file="${backup_file}.sha256"

[[ -f "$backup_file" ]] || die "备份文件不存在：$backup_file"
[[ -f "$checksum_file" ]] || die "校验文件不存在：$checksum_file"

typeset relative_path target_path
for relative_path in "${DOTFILES_MANAGED_TARGETS[@]}"; do
  is_safe_relative_target "$relative_path" || die "受管目标不安全：$relative_path"
  target_path="$HOME/$relative_path"
  if [[ "$backup_file" == "$target_path" || "$backup_file" == "$target_path/"* ]]; then
    die "备份文件位于待恢复目录内，请先移动备份：$backup_file"
  fi
done

# 自行计算摘要，不执行校验文件中可能包含的路径。
typeset expected_hash checksum_rest actual_hash
IFS=' ' read -r expected_hash checksum_rest < "$checksum_file" || die "无法读取校验文件"
if (( ${#expected_hash} != 64 )) || [[ "$expected_hash" == *[^0-9a-fA-F]* ]]; then
  die "校验文件中的 SHA-256 格式无效"
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual_hash="$(command sha256sum "$backup_file")"
elif command -v shasum >/dev/null 2>&1; then
  actual_hash="$(command shasum -a 256 "$backup_file")"
else
  die "缺少 sha256sum 或 shasum"
fi
actual_hash="${actual_hash%% *}"
[[ "${actual_hash:l}" == "${expected_hash:l}" ]] || die "备份文件校验失败，拒绝恢复"

# 先确认 tar 可完整读取，再限制所有归档成员只能落在受管目标内。
command tar -tzf "$backup_file" >/dev/null || die "备份文件不是有效的 tar.gz 归档"

typeset -i archive_safe=1
typeset archive_entry normalized_entry
while IFS= read -r archive_entry; do
  normalized_entry="${archive_entry#./}"
  normalized_entry="${normalized_entry%/}"
  [[ -z "$normalized_entry" ]] && continue

  if ! is_managed_archive_entry "$normalized_entry"; then
    print -u2 -- "归档包含非预期路径：$archive_entry"
    archive_safe=0
  fi
done < <(command tar -tzf "$backup_file")
(( archive_safe == 1 )) || die "备份路径校验失败，拒绝恢复"

# 先完整解压到临时目录，避免在发现损坏前删除当前配置。
typeset restore_staging
restore_staging="$(command mktemp -d "${TMPDIR:-/tmp}/dotfiles-restore.XXXXXX")" \
  || die "无法创建恢复临时目录"

cleanup_staging() {
  [[ -n "${restore_staging:-}" && -d "$restore_staging" ]] \
    && command rm -rf "$restore_staging"
}
trap cleanup_staging EXIT HUP INT TERM

command tar -C "$restore_staging" -xzpf "$backup_file"

print -- "即将使用以下备份覆盖当前 dotfiles："
print -- "  $backup_file"
print -- "恢复前会删除以下路径："
for relative_path in "${DOTFILES_MANAGED_TARGETS[@]}"; do
  print -- "  $HOME/$relative_path"
done

if (( auto_confirm == 0 )); then
  typeset reply
  if ! read -r "reply?确认恢复？输入 y 继续 [y/N]："; then
    die "无法读取确认输入"
  fi
  [[ "$reply" == [yY] ]] || die "已取消恢复"
fi

for relative_path in "${DOTFILES_MANAGED_TARGETS[@]}"; do
  target_path="$HOME/$relative_path"
  command rm -rf "$target_path"

  typeset staged_path="$restore_staging/$relative_path"
  if [[ -e "$staged_path" || -L "$staged_path" ]]; then
    command mkdir -p "${target_path:h}"
    command mv "$staged_path" "$target_path"
  fi
done

print -- "恢复完成。新开一个登录 Shell 后生效。"
