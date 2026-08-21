#!/usr/bin/env zsh

# 受管目标的唯一注册表。
#
# 每条记录依次为：实际相对路径、内置 renderer、支持的平台、是否备份、目标权限。
# 备份、恢复和 apply 都 source 本文件，因此不会再维护第二份目标数组，也不需要
# TOML 解析器或外部配置管理器。

typeset _dotfiles_this_file="${${(%):-%x}:A}"
typeset _dotfiles_script_dir="${DOTFILES_SCRIPT_DIR:-${_dotfiles_this_file:h}}"
if [[ -r "$_dotfiles_script_dir/dotfiles-common.zsh" ]]; then
  source "$_dotfiles_script_dir/dotfiles-common.zsh"
else
  print -u2 -- "错误：缺少共享脚本：$_dotfiles_script_dir/dotfiles-common.zsh"
  exit 1
fi

typeset -ga DOTFILES_TARGET_REGISTRY=(
  $'.zshrc\tzshrc\tdarwin,linux\t1\t600'
  $'.zprofile\tzprofile\tdarwin,linux\t1\t600'
  $'.zimrc\tzimrc\tdarwin,linux\t1\t644'
  $'.vimrc\tvimrc\tdarwin,linux\t1\t644'
  $'.gitconfig\tgitconfig\tdarwin,linux\t1\t600'
  $'.npmrc\tnpmrc\tdarwin,linux\t1\t600'
  $'.ssh/config\tssh_config\tdarwin,linux\t1\t600'
  $'.config/gh/config.yml\tgh_config\tdarwin,linux\t1\t644'
)

typeset -ga DOTFILES_MANAGED_TARGETS=()
typeset -ga DOTFILES_MANAGED_RENDERERS=()
typeset -ga DOTFILES_MANAGED_BACKUPS=()
typeset -ga DOTFILES_MANAGED_MODES=()
typeset -ga DOTFILES_BACKUP_TARGETS=()
typeset -ga DOTFILES_BACKUP_MODES=()

dotfiles_load_targets() {
  local platform="${1:-${DOTFILES_PLATFORM:-}}"
  local record path renderer platforms backup mode supported candidate
  local -i index=0
  local -A seen_paths=() seen_renderers=()

  [[ "$platform" == darwin || "$platform" == linux ]] \
    || dotfiles_die "平台只支持 darwin 或 linux：$platform"

  DOTFILES_MANAGED_TARGETS=()
  DOTFILES_MANAGED_RENDERERS=()
  DOTFILES_MANAGED_BACKUPS=()
  DOTFILES_MANAGED_MODES=()
  DOTFILES_BACKUP_TARGETS=()
  DOTFILES_BACKUP_MODES=()

  for record in "${DOTFILES_TARGET_REGISTRY[@]}"; do
    IFS=$'\t' read -r path renderer platforms backup mode <<< "$record"
    dotfiles_is_safe_relative_path "$path" \
      || dotfiles_die "目标注册表中的路径不安全：$path"

    case "$renderer" in
      zshrc|zprofile|zimrc|vimrc|gitconfig|npmrc|ssh_config|gh_config) ;;
      *) dotfiles_die "目标注册表中的 renderer 不受支持：$renderer" ;;
    esac

    [[ -z "${seen_paths[$path]-}" ]] \
      || dotfiles_die "目标注册表包含重复路径：$path"
    [[ -z "${seen_renderers[$renderer]-}" ]] \
      || dotfiles_die "目标注册表包含重复 renderer：$renderer"
    seen_paths[$path]=1
    seen_renderers[$renderer]=1

    [[ -n "$platforms" ]] \
      || dotfiles_die "目标注册表中的 platforms 不能为空：$path"
    supported=0
    for candidate in "${(@s:,:)platforms}"; do
      case "$candidate" in
        darwin|linux)
          [[ "$candidate" == "$platform" ]] && supported=1
          ;;
        *) dotfiles_die "目标注册表中的平台无效：$candidate" ;;
      esac
    done
    [[ "$backup" == 0 || "$backup" == 1 ]] \
      || dotfiles_die "目标注册表中的 backup 必须为 0 或 1：$path"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] \
      || dotfiles_die "目标注册表中的权限无效：$path ($mode)"
    if (( ${#mode} == 4 )); then
      mode="${mode#0}"
    fi

    if (( supported )); then
      DOTFILES_MANAGED_TARGETS+=("$path")
      DOTFILES_MANAGED_RENDERERS+=("$renderer")
      DOTFILES_MANAGED_BACKUPS+=("$backup")
      DOTFILES_MANAGED_MODES+=("$mode")
      if [[ "$backup" == 1 ]]; then
        DOTFILES_BACKUP_TARGETS+=("$path")
        DOTFILES_BACKUP_MODES+=("$mode")
      fi
    fi
    (( index += 1 ))
  done

  (( index > 0 )) || dotfiles_die "目标注册表为空"
  (( ${#DOTFILES_MANAGED_TARGETS[@]} > 0 )) \
    || dotfiles_die "当前平台没有启用任何受管目标：$platform"
}

typeset _dotfiles_effective_platform="${DOTFILES_PLATFORM:-$(dotfiles_detect_platform)}"
dotfiles_load_targets "$_dotfiles_effective_platform"

if [[ "${ZSH_EVAL_CONTEXT:-}" == toplevel ]]; then
  # 直接执行时输出当前平台的目标列表；被 source 时数组已同步可用。
  typeset -i _dotfiles_index=1
  while (( _dotfiles_index <= ${#DOTFILES_MANAGED_TARGETS[@]} )); do
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "${DOTFILES_MANAGED_TARGETS[$_dotfiles_index]}" \
      "${DOTFILES_MANAGED_RENDERERS[$_dotfiles_index]}" \
      "${DOTFILES_MANAGED_BACKUPS[$_dotfiles_index]}" \
      "${DOTFILES_MANAGED_MODES[$_dotfiles_index]}" \
      "$_dotfiles_effective_platform"
    (( _dotfiles_index += 1 ))
  done
fi

unset _dotfiles_this_file _dotfiles_script_dir _dotfiles_effective_platform
