# Dotfiles

## 写给人看

macOS 和 Linux 通用的 Zsh、Vim、Git、npm、SSH、gh 配置。脚本把仓库里的片段拼成普通文件写进 `~`，不用软链接。

### 包含什么

- 提示符 `[用户:路径]$`，颜色是 256 色编号：括号和冒号 46（绿），用户名 82（黄绿），路径 201（品红），`$` 196（红，root 下显示 `#`）。定义在 `apps/zsh/shared/interactive/theme.zsh`。
- Zsh 插件用 [Zim](https://github.com/zimfw/zimfw) 管理：补全、语法高亮、自动建议，↑/↓ 按已输入的内容搜索历史。
- `ls` 在终端里按行排成紧凑的多列。输出不是终端，或者带了 `-l`、长选项、多个路径时，直接用系统 `ls`。
- 历史在多个终端间共享并去重，空格开头的命令不记录。
- alias 和函数：`tl` / `ta`（tmux ls / attach）、`rsy`（rsync -avz --progress，走 SSH）、`mosh`（固定 IPv4 和 UDP 60000–60020）、`tgz` / `untgz`（打包 / 解包 .tar.gz）。macOS 上还有 `cb`（把文件内容或命令输出复制到剪贴板）、`zzz`（关显示器）、`awake` / `slp`（禁止睡眠 / 恢复睡眠并立即睡眠）。
- Vim 只配了 Option 键：Insert、Normal、命令行模式下，Option+←/→ 按词移动，Option+Backspace 删前一个词，Option+Fn+Backspace 删后一个词。终端要把 Option 组合键发成 Esc 前缀序列，在 iTerm2 上验证过。
- Git 只设了 `http.version = HTTP/1.1`；SSH 对所有主机开 keepalive；gh 加了 `co`（`gh pr checkout`）。

### 注意

- 开了 `NO_CLOBBER`：`>` 不会覆盖已有文件，要覆盖用 `>|`。
- macOS 的 Homebrew 用清华镜像。不需要就删掉 `apps/zsh/platform/darwin/profile.zsh` 里的三个 `HOMEBREW_*`。
- Vim 里 Esc 后 1 秒内按的 `b`、`f`、`d`、退格，会和 Esc 一起被当成 Option 组合键。比如快速按 Esc、`d`、`d`，删掉的是一个词，不是一整行。

### 安装

需要 zsh、git 和 curl（或 wget）。第一次启动 zsh 时会联网安装 Zim 和插件。NVM、Homebrew 装了就会自动加载。

apply 会用生成的内容整个替换这些文件：`~/.zshrc`、`~/.zprofile`、`~/.zimrc`、`~/.vimrc`、`~/.gitconfig`、`~/.npmrc`、`~/.ssh/config`、`~/.config/gh/config.yml`。

```zsh
git clone https://github.com/keeperhihi/dotfile.git
cd dotfile
zsh scripts/backup-dotfiles.zsh        # 先备份这些文件
# 把要保留的设置搬进 private/，至少 Git 身份和 SSH 主机，见下一节
zsh scripts/apply-dotfiles.zsh --diff  # 预览改动
zsh scripts/apply-dotfiles.zsh
exec zsh -l
```

备份在 `~/.local/state/dotfiles-backups/`。不想用了，就拿它恢复：

```zsh
zsh scripts/restore-dotfiles.zsh ~/.local/state/dotfiles-backups/dotfiles-YYYYMMDD-HHMMSS.tar.gz
```

以后改配置就改仓库里的文件，再跑一次 apply。直接改 `~/.zshrc` 这类生成的文件，下次 apply 会被覆盖。

### 私有配置

`apps/` 提交到 Git。`private/` 被 `.gitignore` 忽略，放不该公开或只属于这台机器的东西：身份、token、代理、内网主机、私钥路径。

每个目标文件按下表顺序拼接。`private/` 里的文件可以没有，有的话以它为准。

| 目标 | 来源（按顺序） |
| --- | --- |
| `~/.zprofile` | `apps/zsh` → `private/zsh/environment.zsh` → `private/zsh/profile.zsh` |
| `~/.zshrc` | `apps/zsh` → `private/zsh/environment.zsh` → `private/zsh/interactive.zsh` |
| `~/.vimrc` | `apps/vim/vimrc` → `private/vim/vimrc` |
| `~/.gitconfig` | `apps/git/gitconfig` → `private/git/gitconfig` |
| `~/.npmrc` | `apps/npm/npmrc` → `private/npm/npmrc` |
| `~/.ssh/config` | `private/ssh/config` → `apps/ssh/config` |
| `~/.zimrc` | `apps/zsh/shared/modules/zim.zsh` |
| `~/.config/gh/config.yml` | `apps/gh/config.yml` |

- SSH 把 private 放在前面，因为 OpenSSH 对同一个选项只取第一次出现的值。
- `apps/zsh` 里各片段的顺序写在 `apps/zsh/manifest.toml`：先共享片段，再 `platform/darwin` 或 `platform/linux`。新加的 zsh 文件要写进 manifest 才会加载。
- 环境变量放 `private/zsh/environment.zsh`，登录 shell 和交互 shell 都会加载它；alias 和函数放 `private/zsh/interactive.zsh`。

比如设置 Git 身份：

```zsh
mkdir -p private/git
git config --file private/git/gitconfig user.name "Your Name"
git config --file private/git/gitconfig user.email "you@example.com"
zsh scripts/apply-dotfiles.zsh
```

`private/` 不在 Git 里，换机器时要自己拷过去，备份包里也有一份。

### 常用命令

```zsh
zsh scripts/apply-dotfiles.zsh              # 生成并写入 ~
zsh scripts/apply-dotfiles.zsh --diff       # 只看 diff
zsh scripts/apply-dotfiles.zsh --check      # 有差异时返回 1
zsh scripts/backup-dotfiles.zsh             # 备份目标文件和 private/
zsh scripts/restore-dotfiles.zsh <archive>  # 从备份恢复目标文件和 private/，会先确认
zsh scripts/publish-dotfiles.zsh            # 用固定信息提交全部改动，推送到 origin main
zsh tests/apply-dotfiles.zsh                # 回归测试，只用临时目录
```

apply 的 `--home <dir>`、`--platform darwin|linux` 可以把配置生成到别的目录、按另一个平台生成，其余选项看 `--help`。恢复时 `.sha256` 文件要和备份包放在一起。

## 写给 Agent

先读 `AGENTS.md`。注释和脚本输出用中文。

### 要点

- 拼接逻辑在 `scripts/apply-dotfiles.zsh` 的 `render_zsh_target` 和 `render_plain_target`。目标路径、平台、权限登记在 `scripts/managed-targets.zsh`，backup 和 restore 读的也是这份登记。
- `apps/zsh/manifest.toml` 由 `dotfiles_manifest_sources` 解析，只认双引号字符串，单引号条目会被静默跳过。
- `apps/zsh/shared/modules/zim.zsh` 是 `~/.zimrc` 的源码，不能写进 manifest。
- `~/.config/gh/hosts.yml` 是 gh 的登录凭据，不受管理，不要读写。
- 目标文件是复制出去的。改 `apps/` 或 `private/` 后重新 apply，不要直接改 `$HOME` 里的目标文件。
- `private/` 只留在本地：不要 `git add -f`，也不要把其中的内容写进 `apps/`。

### 帮用户部署

用户刚 clone 完、让你把配置装上时：

1. 问用户有没有现成的 `private/`（来自另一台机器或备份包），有就先放到仓库根目录。
2. 跑 `zsh scripts/apply-dotfiles.zsh --dry-run` 和 `--diff`，看清哪些现有文件会被替换。两者都不写入。
3. 读这些文件，把还要保留的内容按上文的表搬进 `private/<app>/`：Git 身份和凭据设置、SSH 主机、npm registry 和 token、代理、本机 PATH 和工具初始化。`~/.zimrc` 和 `~/.config/gh/config.yml` 没有 private 层，要保留只能改 `apps/`，先问用户。
4. 按「验证」在临时 HOME 里跑一遍。
5. 跑 `zsh scripts/backup-dotfiles.zsh`，把真实 HOME 的 `--diff` 给用户看，用户同意后再 apply，然后跑 `--check`。
6. 让用户执行 `exec zsh -l`。首次启动会联网安装 Zim。

`apps/` 里的提示符、alias、Homebrew 镜像和 Vim 映射是作者的个人偏好，留不留由用户决定。

### 需要用户确认

- 写入真实 HOME 的 apply（不带 `--diff`、`--dry-run`、`--check`）：会替换用户现有的配置。
- `restore-dotfiles.zsh`：会删除当前目标文件并整体替换 `private/`。用户没要求就不加 `--yes`。
- `publish-dotfiles.zsh`：会 `git add .`、提交并推送。

### 验证

```zsh
zsh tests/apply-dotfiles.zsh

for platform in darwin linux; do
  tmp_home="$(mktemp -d)"
  zsh scripts/apply-dotfiles.zsh --home "$tmp_home" --platform "$platform"
  zsh scripts/apply-dotfiles.zsh --home "$tmp_home" --platform "$platform" --check
  zsh -n "$tmp_home/.zshrc"
  zsh -n "$tmp_home/.zprofile"
  vim -Nu "$tmp_home/.vimrc" -n -es +'qa!'
  git config --file "$tmp_home/.gitconfig" --list >/dev/null
  ssh -G -F "$tmp_home/.ssh/config" example.com >/dev/null
  rm -rf "$tmp_home"
done
```

结束时 `git status` 里不应出现 `private/` 下的文件，`apps/` 里不应有凭据。

### 新增受管文件

1. `scripts/managed-targets.zsh`：在 `DOTFILES_TARGET_REGISTRY` 加一条，并把新 renderer 加进校验 renderer 的 `case`。
2. `scripts/apply-dotfiles.zsh`：在 `render_plain_target` 加分支，写明 shared 和 private 源码路径。
3. `.gitignore`：在“临时 HOME 位于仓库根目录时生成的目标”一节加 `/<目标路径>`。
4. 检查 `backup-dotfiles.zsh` 和 `restore-dotfiles.zsh` 是否要跟着改。
5. 更新本 README「写给人看」里的文件列表和表格。
