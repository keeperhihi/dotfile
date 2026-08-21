#!/usr/bin/env zsh

# Shared, dependency-free helpers for the dotfiles scripts.
# This file is sourced by the scripts in this directory; it is not a target
# configuration and never becomes part of a generated HOME file.

dotfiles_die() {
  print -u2 -- "错误：$*"
  exit 1
}

dotfiles_detect_platform() {
  case "${DOTFILES_PLATFORM:-}" in
    darwin|linux)
      print -r -- "$DOTFILES_PLATFORM"
      return 0
      ;;
    "")
      ;;
    *)
      dotfiles_die "平台只支持 darwin 或 linux：$DOTFILES_PLATFORM"
      ;;
  esac

  command -v uname >/dev/null 2>&1 \
    || dotfiles_die "缺少 uname 命令，无法检测平台"
  case "$(command uname -s)" in
    Darwin) print -r -- darwin ;;
    Linux) print -r -- linux ;;
    *) dotfiles_die "不支持的操作系统：$(command uname -s)" ;;
  esac
}

dotfiles_is_safe_relative_path() {
  local value="${1:-}"
  local component
  [[ -n "$value" && "$value" != "." && "$value" != ".." \
    && "$value" != /* && "$value" != *$'\n'* && "$value" != *$'\t'* \
    && "$value" != *'//'* ]] || return 1
  for component in "${(@s:/:)value}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. \
      && "$component" != -* ]] || return 1
  done
  return 0
}

dotfiles_require_absolute_directory() {
  local label="$1"
  local path="$2"
  [[ -n "$path" && "$path" == /* && "$path" != "/" \
    && "$path" != *$'\n'* && "$path" != *$'\t'* ]] \
    || dotfiles_die "$label 目录无效：$path"
  [[ -d "$path" ]] || dotfiles_die "$label 目录不存在：$path"
  [[ ! -L "$path" ]] || dotfiles_die "$label 目录不能是符号链接：$path"
}

dotfiles_mode() {
  local file_path="$1"
  local value host_os
  host_os="$(command uname -s 2>/dev/null)" \
    || dotfiles_die "无法检测系统类型，无法读取文件权限：$file_path"
  case "$host_os" in
    Darwin)
      value="$(command stat -f '%Lp' "$file_path" 2>/dev/null)" || value=""
      ;;
    Linux)
      value="$(command stat -c '%a' "$file_path" 2>/dev/null)" || value=""
      ;;
    *)
      # 仅为其他 BSD 风格系统保留顺序回退；正式支持平台是 macOS/Linux。
      value="$(command stat -f '%Lp' "$file_path" 2>/dev/null)" || value=""
      if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        value="$(command stat -c '%a' "$file_path" 2>/dev/null)" || value=""
      fi
      ;;
  esac
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    print -r -- "$value"
    return 0
  fi
  dotfiles_die "无法读取文件权限：$file_path"
}

dotfiles_normalize_private_permissions() {
  local tree="$1"
  [[ -e "$tree" || -L "$tree" ]] || return 0
  [[ -d "$tree" && ! -L "$tree" ]] \
    || dotfiles_die "private 路径必须是目录且不能是符号链接：$tree"
  # 归档解压可能恢复出不可遍历的目录权限；先只提升 owner 权限，随后再
  # 把目录固定为 700、普通文件固定为 600。chmod -R 不跟随目录内的符号链接。
  command chmod -R 700 "$tree" \
    || dotfiles_die "无法准备 private 权限：$tree"
  local links
  links="$(command find "$tree" -type l -print -quit)" \
    || dotfiles_die "无法检查 private 符号链接：$tree"
  [[ -z "$links" ]] \
    || dotfiles_die "private 源码不能包含符号链接：$tree"
  dotfiles_reject_special_files_in_tree "$tree" "private 源码"
  command chmod 700 "$tree" \
    || dotfiles_die "无法设置 private 目录权限：$tree"
  command find "$tree" -type d -exec chmod 700 {} + \
    || dotfiles_die "无法设置 private 子目录权限：$tree"
  command find "$tree" -type f -exec chmod 600 {} + \
    || dotfiles_die "无法设置 private 文件权限：$tree"
}

dotfiles_reject_symlinks_in_tree() {
  local tree="$1"
  local label="$2"
  local links
  [[ -d "$tree" && ! -L "$tree" ]] \
    || dotfiles_die "$label 目录不存在或是符号链接：$tree"
  links="$(command find "$tree" -type l -print -quit)" \
    || dotfiles_die "无法检查 $label 的符号链接：$tree"
  [[ -z "$links" ]] \
    || dotfiles_die "$label 不能包含符号链接：$tree"
}

dotfiles_reject_special_files_in_tree() {
  local tree="$1"
  local label="$2"
  local file_type entries
  [[ -d "$tree" && ! -L "$tree" ]] \
    || dotfiles_die "$label 目录不存在或是符号链接：$tree"
  for file_type in b c p s; do
    entries="$(command find "$tree" -type "$file_type" -print -quit)" \
      || dotfiles_die "无法检查 $label 的特殊文件：$tree"
    [[ -z "$entries" ]] \
      || dotfiles_die "$label 包含特殊文件：$tree"
  done
}

dotfiles_require_regular_file() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] \
    || dotfiles_die "源码文件不存在、不是普通文件或是符号链接：$path"
}

dotfiles_is_special_file() {
  local file_path="$1"
  [[ -b "$file_path" || -c "$file_path" || -p "$file_path" || -S "$file_path" ]]
}

dotfiles_append_fragment() {
  local source_file="$1"
  local output_file="$2"
  dotfiles_require_regular_file "$source_file"
  command cat "$source_file" >> "$output_file" \
    || dotfiles_die "无法读取源码片段：$source_file"
  # 每个片段之后强制补一个换行，避免下一个片段粘在最后一行。
  print -r >> "$output_file"
}

dotfiles_validate_parent_chain() {
  local path="$1"
  local root="$2"
  local parent="${path:h}"
  [[ "$root" == /* && "$path" == "$root"/* ]] \
    || dotfiles_die "路径不在预期根目录下：$path"
  while [[ "$parent" == "$root"/* ]]; do
    [[ ! -L "$parent" ]] \
      || dotfiles_die "目标父目录是符号链接，拒绝写入：$parent"
    [[ ! -e "$parent" || -d "$parent" ]] \
      || dotfiles_die "目标父路径不是目录，拒绝写入：$parent"
    parent="${parent:h}"
  done
}

dotfiles_manifest_sources() {
  local manifest="$1"
  local section="$2"
  local key="$3"
  local line trimmed rest value
  local -i in_section=0 collecting=0 found=0
  local -a values=()

  dotfiles_require_regular_file "$manifest"
  setopt localoptions extendedglob

  while IFS= read -r line || [[ -n "$line" ]]; do
    # 当前 manifest 的值都是简单双引号字符串；注释不会出现在字符串中。
    line="${line%%\#*}"
    trimmed="${line##[[:space:]]#}"
    trimmed="${trimmed%%[[:space:]]#}"

    if [[ "$trimmed" == "[$section]" ]]; then
      in_section=1
      collecting=0
      continue
    fi
    if [[ "$trimmed" == \[*\] ]]; then
      in_section=0
      collecting=0
      continue
    fi
    (( in_section )) || continue

    if (( ! collecting )); then
      [[ "$trimmed" == "$key"* ]] || continue
      rest="${trimmed#$key}"
      rest="${rest##[[:space:]]#}"
      [[ "$rest" == '='* ]] || continue
      rest="${rest#=}"
      rest="${rest##[[:space:]]#}"
      [[ "$rest" == \[* ]] \
        || dotfiles_die "manifest 中的数组格式无效：$manifest [$section].$key"
      collecting=1
      found=1
    else
      rest="$trimmed"
    fi

    while [[ "$rest" == *\"* ]]; do
      rest="${rest#*\"}"
      [[ "$rest" == *\"* ]] \
        || dotfiles_die "manifest 中存在未闭合字符串：$manifest"
      value="${rest%%\"*}"
      dotfiles_is_safe_relative_path "$value" \
        || dotfiles_die "manifest 路径不安全：$value"
      values+=("$value")
      rest="${rest#*\"}"
    done
    [[ "$rest" == *\]* ]] && collecting=0
  done < "$manifest"

  (( found && ! collecting )) \
    || dotfiles_die "manifest 缺少完整数组：$manifest [$section].$key"
  (( ${#values[@]} > 0 )) \
    || dotfiles_die "manifest 数组不能为空：$manifest [$section].$key"
  DOTFILES_MANIFEST_SOURCES=("${values[@]}")
}
