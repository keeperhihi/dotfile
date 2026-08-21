#!/usr/bin/env zsh

# 将本仓库的全部非 ignored 修改使用固定消息提交，并推送到 origin/main。

emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

typeset script_file="${${(%):-%x}:A}"
typeset script_dir="${script_file:h}"
typeset script_name="${script_file:t}"
typeset repo_root="${script_dir:h}"
typeset commit_message='[updated] dotfiles'

usage() {
  print -u2 -- "用法：$script_name"
  print -u2 -- "  --help  显示帮助"
  exit "${1:-2}"
}

if (( $# > 0 )); then
  if (( $# == 1 )) && [[ "$1" == --help || "$1" == -h ]]; then
    usage 0
  fi
  usage 2
fi

if [[ -r "$script_dir/dotfiles-common.zsh" ]]; then
  source "$script_dir/dotfiles-common.zsh"
else
  print -u2 -- "错误：缺少共享脚本：$script_dir/dotfiles-common.zsh"
  exit 1
fi

command -v git >/dev/null 2>&1 || dotfiles_die "缺少 git 命令"
command -v gh >/dev/null 2>&1 || dotfiles_die "缺少 gh 命令；请先安装 GitHub CLI"

typeset actual_root
actual_root="$(command git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)" \
  || dotfiles_die "脚本所在目录不是 Git 仓库：$repo_root"
actual_root="${actual_root:A}"
repo_root="${repo_root:A}"
[[ "$actual_root" == "$repo_root" ]] \
  || dotfiles_die "脚本必须位于仓库根目录下的 scripts 目录：$repo_root"

typeset current_branch
current_branch="$(command git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null)" \
  || dotfiles_die "当前不在任何 Git branch 上"
[[ "$current_branch" == main ]] \
  || dotfiles_die "当前 branch 是 $current_branch；只允许在 main 上自动提交"

command git -C "$repo_root" remote get-url origin >/dev/null 2>&1 \
  || dotfiles_die "本仓库没有 origin remote"

command gh auth status --active --hostname github.com >/dev/null 2>&1 \
  || dotfiles_die "GitHub CLI 未登录；请先执行 gh auth login"

typeset conflicted_paths
conflicted_paths="$(command git -C "$repo_root" diff --name-only --diff-filter=U)"
[[ -z "$conflicted_paths" ]] \
  || dotfiles_die "仓库存在未解决的 merge conflict，拒绝自动提交"

typeset tracked_private
tracked_private="$(command git -C "$repo_root" ls-files private)"
[[ -z "$tracked_private" ]] \
  || dotfiles_die "private/ 中存在已跟踪文件，拒绝自动提交"
if [[ -e "$repo_root/private" || -L "$repo_root/private" ]]; then
  command git -C "$repo_root" check-ignore -q private \
    || dotfiles_die "private/ 未被 Git ignore，拒绝自动提交"
fi

cd "$repo_root"
command git add .

if command git diff --cached --quiet; then
  print -- "没有可提交的修改。"
  exit 0
fi

command git commit -m "$commit_message"
if ! command git push origin main; then
  print -u2 -- "错误：commit 已保留在本地，但推送 origin/main 失败"
  exit 1
fi

print -- "发布完成：$commit_message -> origin/main"
