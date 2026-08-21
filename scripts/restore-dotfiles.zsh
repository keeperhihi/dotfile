#!/usr/bin/env zsh

# 恢复 backup-dotfiles.zsh 创建的新格式快照。
# 归档必须同时包含 home/ 与 private/，并先完整 staging、校验和确认后才写回。

emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077

typeset script_file="${${(%):-%x}:A}"
typeset script_dir="${script_file:h}"
typeset script_name="${script_file:t}"
typeset home_arg="${HOME:-}"
typeset source_arg="${DOTFILES_SOURCE_DIR:-${script_dir:h}}"
typeset platform_arg="${DOTFILES_PLATFORM:-}"
typeset -i auto_confirm=0

typeset backup_arg=""

usage() {
  print -u2 -- "用法：$script_name [--yes] [--home PATH] [--source PATH] [--platform darwin|linux] <dotfiles-YYYYMMDD-HHMMSS.tar.gz>"
  print -u2 -- "  --yes                    跳过交互确认"
  print -u2 -- "  --home PATH              覆盖目标 HOME"
  print -u2 -- "  --source PATH            覆盖仓库源码目录"
  print -u2 -- "  --platform darwin|linux  覆盖平台检测"
  print -u2 -- "  --help                   显示帮助"
  exit 2
}

while (( $# > 0 )); do
  case "$1" in
    --yes) auto_confirm=1 ;;
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
    --help|-h) usage ;;
    -*) print -u2 -- "错误：未知选项：$1"; usage ;;
    *)
      [[ -z "$backup_arg" ]] || usage
      backup_arg="$1"
      ;;
  esac
  shift
done
[[ -n "$backup_arg" ]] || usage

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
[[ ! -L "$backup_arg" ]] \
  || dotfiles_die "备份文件不能是符号链接：$backup_arg"
[[ ! -L "$backup_arg.sha256" ]] \
  || dotfiles_die "校验文件不能是符号链接：$backup_arg.sha256"
typeset backup_file="${backup_arg:A}"
typeset checksum_file="${backup_file}.sha256"
[[ -f "$backup_file" && ! -L "$backup_file" ]] \
  || dotfiles_die "备份文件不存在或是符号链接：$backup_file"
[[ -f "$checksum_file" && ! -L "$checksum_file" ]] \
  || dotfiles_die "校验文件不存在或是符号链接：$checksum_file"

# 备份不能位于即将删除的 HOME 目标或 private 源码内。
typeset relative_path target_path
for relative_path in "${DOTFILES_MANAGED_TARGETS[@]}"; do
  dotfiles_is_safe_relative_path "$relative_path" \
    || dotfiles_die "受管目标不安全：$relative_path"
  target_path="$home_arg/$relative_path"
  dotfiles_validate_parent_chain "$target_path" "$home_arg"
  if [[ "$backup_file" == "$target_path" || "$backup_file" == "$target_path/"* \
     || "$checksum_file" == "$target_path" || "$checksum_file" == "$target_path/"* ]]; then
    dotfiles_die "备份文件或校验文件位于待恢复目录内，请先移动备份：$backup_file"
  fi
done
[[ "$backup_file" != "$private_dir" && "$backup_file" != "$private_dir/"* \
   && "$checksum_file" != "$private_dir" && "$checksum_file" != "$private_dir/"* ]] \
  || dotfiles_die "备份文件或校验文件位于 private 内，请先移动备份：$backup_file"

# 自行计算摘要，不执行校验文件中可能包含的路径。
typeset expected_hash checksum_rest actual_hash
IFS=' ' read -r expected_hash checksum_rest < "$checksum_file" \
  || dotfiles_die "无法读取校验文件"
[[ "$expected_hash" =~ ^[0-9a-fA-F]{64}$ ]] \
  || dotfiles_die "校验文件中的 SHA-256 格式无效"
if command -v sha256sum >/dev/null 2>&1; then
  actual_hash="$(command sha256sum "$backup_file")"
elif command -v shasum >/dev/null 2>&1; then
  actual_hash="$(command shasum -a 256 "$backup_file")"
else
  dotfiles_die "缺少 sha256sum 或 shasum"
fi
actual_hash="${actual_hash%%[[:space:]]*}"
[[ "${actual_hash:l}" == "${expected_hash:l}" ]] \
  || dotfiles_die "备份文件校验失败，拒绝恢复"

command -v tar >/dev/null 2>&1 || dotfiles_die "缺少 tar 命令"
command -v mktemp >/dev/null 2>&1 || dotfiles_die "缺少 mktemp 命令"
command -v awk >/dev/null 2>&1 || dotfiles_die "缺少 awk 命令"

typeset archive_listing archive_details
archive_listing=""
archive_listing="$(command tar -tzf "$backup_file")" \
  || dotfiles_die "备份文件不是有效的 tar.gz 归档"
archive_details="$(command tar -tvzf "$backup_file")" \
  || dotfiles_die "无法读取备份归档成员"

# 在任何解压前拒绝危险成员，避免归档成员互相穿透 staging。
typeset archive_detail archive_type archive_member
while IFS= read -r archive_detail || [[ -n "$archive_detail" ]]; do
  [[ -n "$archive_detail" ]] || continue
  archive_type="${archive_detail[1]}"
  if [[ "$archive_type" == l ]]; then
    archive_member="$(print -r -- "$archive_detail" | command awk '{for (i = 1; i <= NF; i++) if ($i == "->" && i > 1) { print $(i - 1); exit }}')"
    archive_member="${archive_member#./}"
    [[ "$archive_member" == home/* ]] \
      || dotfiles_die "private 或其他前缀包含符号链接，拒绝恢复"
    archive_member="${archive_member#home/}"
    typeset -i exact_target
    exact_target=0
    for relative_path in "${DOTFILES_BACKUP_TARGETS[@]}"; do
      [[ "$archive_member" == "$relative_path" ]] && exact_target=1
    done
    (( exact_target )) \
      || dotfiles_die "归档符号链接不是注册目标本身，拒绝恢复：$archive_detail"
  elif [[ "$archive_type" != d && "$archive_type" != - ]]; then
    dotfiles_die "归档包含不受支持的成员类型：$archive_detail"
  fi
done <<< "$archive_details"

is_managed_archive_entry() {
  local entry="$1"
  local managed_target
  dotfiles_is_safe_relative_path "$entry" || return 1
  for managed_target in "${DOTFILES_BACKUP_TARGETS[@]}"; do
    # tar 会写入目标的父目录；只允许注册目标本身及其父目录。
    if [[ "$entry" == "$managed_target" || "$managed_target" == "$entry" \
       || "$managed_target" == "$entry/"* ]]; then
      return 0
    fi
  done
  return 1
}

is_exact_managed_target() {
  local entry="$1"
  local managed_target
  for managed_target in "${DOTFILES_BACKUP_TARGETS[@]}"; do
    [[ "$entry" == "$managed_target" ]] && return 0
  done
  return 1
}

typeset -i archive_safe=1 saw_home=0 saw_private=0
typeset archive_entry normalized_entry archive_path
while IFS= read -r archive_entry || [[ -n "$archive_entry" ]]; do
  normalized_entry="${archive_entry#./}"
  normalized_entry="${normalized_entry%/}"
  [[ -n "$normalized_entry" ]] || continue

  if [[ "$normalized_entry" == home ]]; then
    saw_home=1
  elif [[ "$normalized_entry" == private ]]; then
    saw_private=1
  elif [[ "$normalized_entry" == home/* ]]; then
    archive_path="${normalized_entry#home/}"
    if ! is_managed_archive_entry "$archive_path"; then
      print -u2 -- "归档包含非预期 HOME 路径：$archive_entry"
      archive_safe=0
    fi
  elif [[ "$normalized_entry" == private/* ]]; then
    archive_path="${normalized_entry#private/}"
    if ! dotfiles_is_safe_relative_path "$archive_path"; then
      print -u2 -- "归档包含不安全 private 路径：$archive_entry"
      archive_safe=0
    fi
  else
    print -u2 -- "归档缺少受支持的前缀：$archive_entry"
    archive_safe=0
  fi
done <<< "$archive_listing"
(( saw_home && saw_private )) \
  || dotfiles_die "归档必须同时包含 home/ 与 private/"
(( archive_safe )) || dotfiles_die "备份路径校验失败，拒绝恢复"

# 仅在完成所有校验后解压 staging。
typeset restore_staging=""
cleanup_staging() {
  if [[ -n "${restore_staging:-}" && -d "$restore_staging" ]]; then
    command chmod -R 700 "$restore_staging" 2>/dev/null || true
    command rm -rf "$restore_staging"
  fi
}
trap cleanup_staging EXIT HUP INT TERM
restore_staging="$(command mktemp -d "${TMPDIR:-/tmp}/dotfiles-restore.XXXXXX")" \
  || dotfiles_die "无法创建恢复临时目录"
command tar -C "$restore_staging" -xzpf "$backup_file" \
  || dotfiles_die "无法解压备份归档"
[[ -d "$restore_staging/home" && -d "$restore_staging/private" ]] \
  || dotfiles_die "归档 staging 缺少 home/ 或 private/"
# tar 会恢复归档中声明的目录权限；先让 staging 可遍历，再做成员检查。
command chmod -R 700 "$restore_staging/home" "$restore_staging/private" \
  || dotfiles_die "无法准备恢复 staging 权限"
dotfiles_normalize_private_permissions "$restore_staging/private"

# private staging 不允许符号链接；HOME 只允许注册目标本身是符号链接。
dotfiles_reject_symlinks_in_tree "$restore_staging/private" "private 归档"
typeset home_symlinks
home_symlinks="$(command find "$restore_staging/home" -type l -print)" \
  || dotfiles_die "无法检查 HOME staging 符号链接"
typeset staged_link staged_relative
while IFS= read -r staged_link || [[ -n "$staged_link" ]]; do
  [[ -n "$staged_link" ]] || continue
  staged_relative="${staged_link#"$restore_staging/home/"}"
  is_exact_managed_target "$staged_relative" \
    || dotfiles_die "HOME staging 符号链接不是注册目标本身：$staged_relative"
done <<< "$home_symlinks"

dotfiles_reject_special_files_in_tree "$restore_staging/private" "private 归档"
dotfiles_reject_special_files_in_tree "$restore_staging/home" "HOME 归档"

typeset -i target_index=1
for relative_path in "${DOTFILES_BACKUP_TARGETS[@]}"; do
  target_path="$restore_staging/home/$relative_path"
  if [[ -d "$target_path" && ! -L "$target_path" ]]; then
    dotfiles_die "归档把文件目标伪装成目录，拒绝恢复：$relative_path"
  fi
  dotfiles_validate_parent_chain "$target_path" "$restore_staging/home"
done

# 写回前一次性检查当前 HOME 目标和 private 根，避免确认后才发现危险路径而
# 只删除了一部分目标。
for relative_path in "${DOTFILES_BACKUP_TARGETS[@]}"; do
  target_path="$home_arg/$relative_path"
  if [[ -d "$target_path" && ! -L "$target_path" ]]; then
    dotfiles_die "当前 HOME 目标是目录，拒绝恢复：$target_path"
  fi
  if [[ ! -L "$target_path" ]] && dotfiles_is_special_file "$target_path"; then
    dotfiles_die "当前 HOME 目标是特殊文件，拒绝恢复：$target_path"
  fi
done
[[ ! -L "$private_dir" ]] \
  || dotfiles_die "当前 private 目录是符号链接，拒绝写回：$private_dir"
[[ ! -e "$private_dir" || -d "$private_dir" ]] \
  || dotfiles_die "当前 private 路径不是目录，拒绝写回：$private_dir"

print -- "即将使用以下备份覆盖当前 dotfiles："
print -- "  $backup_file"
print -- "恢复前会删除以下 HOME 目标："
for relative_path in "${DOTFILES_BACKUP_TARGETS[@]}"; do
  print -- "  $home_arg/$relative_path"
done
print -- "恢复仓库 private 源码："
print -- "  $private_dir"

if (( ! auto_confirm )); then
  if [[ -t 0 ]]; then
    print -n -u2 -- "确认恢复？输入 y 继续 [y/N]："
  else
    print -u2 -- "当前不是交互终端；请输入 y 确认恢复，或使用 --yes。"
  fi
  typeset reply=""
  IFS= read -r reply || dotfiles_die "无法读取确认输入"
  [[ "$reply" == [yY] ]] || dotfiles_die "已取消恢复"
fi

# 先替换 HOME 目标；目标父目录已经检查过，不会穿过符号链接。
for relative_path in "${DOTFILES_BACKUP_TARGETS[@]}"; do
  target_path="$home_arg/$relative_path"
  if [[ -d "$target_path" && ! -L "$target_path" ]]; then
    dotfiles_die "当前 HOME 目标是目录，拒绝删除：$target_path"
  fi
  command rm -rf "$target_path"

  typeset staged_target="$restore_staging/home/$relative_path"
  if [[ -e "$staged_target" || -L "$staged_target" ]]; then
    command mkdir -p -m 700 "${target_path:h}"
    command mv "$staged_target" "$target_path"
    if [[ ! -L "$target_path" ]]; then
      command chmod "${DOTFILES_BACKUP_MODES[$target_index]}" "$target_path"
    fi
  fi
  (( target_index += 1 ))
done

# private 是完整源码快照：替换整个目录，避免残留旧片段。
if [[ -e "$private_dir" ]]; then
  command rm -rf "$private_dir"
fi
command mkdir -p "$source_arg"
command mv "$restore_staging/private" "$private_dir"
dotfiles_normalize_private_permissions "$private_dir"

print -- "恢复完成。新开一个登录 Shell 后生效。"
