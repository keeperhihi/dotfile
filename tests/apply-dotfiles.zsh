#!/usr/bin/env zsh

# 在临时 source/HOME 中验证 diff 只读行为与 SSH 私有配置优先级。
emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

typeset test_script="${${(%):-%x}:A}"
typeset repo_root="${test_script:h:h}"
typeset test_root="$(command mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")"
trap 'command rm -rf "$test_root"' EXIT HUP INT TERM

typeset test_source="$test_root/source"
command mkdir -p "$test_source/private/ssh" "$test_source/private/git"
command cp -R "$repo_root/apps" "$test_source/apps"
cat > "$test_source/private/ssh/config" <<'EOF'
Host override-test
    HostName 127.0.0.1
    ServerAliveInterval 5
    ServerAliveCountMax 2
    TCPKeepAlive no
EOF
cat > "$test_source/private/git/gitconfig" <<'EOF'
[http]
    version = HTTP/2
EOF

source "$repo_root/scripts/dotfiles-common.zsh"
typeset -i failures=0
fail() {
  print -u2 -- "失败：$*"
  (( failures += 1 ))
}

typeset test_home platform mode result ssh_settings
typeset -a flags
run_apply() {
  command env HOME="$test_home" zsh -df "$repo_root/scripts/apply-dotfiles.zsh" \
    --source "$test_source" --home "$test_home" --platform "$platform" "$@"
}

for platform in darwin linux; do
  for mode in diff diff-check; do
    test_home="$test_root/$platform-$mode"
    command mkdir -p "$test_home"
    print -rl -- '[user]' '    name = Existing User' > "$test_home/.gitconfig"
    command chmod 644 "$test_home/.gitconfig"
    command cp -Rp "$test_home" "$test_home-before"
    flags=(--diff)
    [[ "$mode" != diff-check ]] || flags+=(--check)
    result=0
    run_apply "${flags[@]}" > "$test_root/output" 2>&1 || result=$?
    if [[ "$mode" == diff ]]; then
      [[ "$result" == 0 ]] || fail "$platform --diff 退出码应为 0，实际为 $result"
    else
      [[ "$result" == 1 ]] || fail "$platform --diff --check 存在差异时应返回 1"
    fi
    command diff -r "$test_home-before" "$test_home" >/dev/null \
      || fail "$platform $mode 修改或创建了 HOME 文件"
    [[ "$(dotfiles_mode "$test_home/.gitconfig")" == 644 ]] \
      || fail "$platform $mode 修改了目标权限"
    command grep -q '^+++ ' "$test_root/output" \
      || fail "$platform $mode 没有输出 unified diff"
  done

  test_home="$test_root/$platform-apply"
  command mkdir -p "$test_home"
  run_apply > "$test_root/output" 2>&1
  run_apply --check >> "$test_root/output" 2>&1
  ssh_settings="$(command ssh -G -F "$test_home/.ssh/config" override-test 2>/dev/null)"
  [[ "$ssh_settings" == *$'serveraliveinterval 5\n'* \
     && "$ssh_settings" == *$'serveralivecountmax 2\n'* \
     && "$ssh_settings" == *$'tcpkeepalive no\n'* ]] \
    || fail "$platform SSH 私有设置未覆盖共享默认值"
  ssh_settings="$(command ssh -G -F "$test_home/.ssh/config" fallback-test 2>/dev/null)"
  [[ "$ssh_settings" == *$'serveraliveinterval 30\n'* \
     && "$ssh_settings" == *$'serveralivecountmax 100\n'* \
     && "$ssh_settings" == *$'tcpkeepalive yes\n'* ]] \
    || fail "$platform SSH 共享默认值未生效"
  [[ "$(command git config --file "$test_home/.gitconfig" http.version)" == HTTP/2 ]] \
    || fail "$platform Git 私有配置覆盖顺序发生变化"
done

(( failures == 0 )) || exit 1
print -- "通过：darwin/linux 渲染的 diff 只读行为、检查退出码与 SSH 配置优先级。"
