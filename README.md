# Dotfiles

这是一个按应用分域、按配置归属分层的跨 macOS/Linux dotfiles 仓库。
仓库完全由原生脚本维护；`scripts/` 中的原生 Zsh 脚本负责渲染、部署、检查、备份和恢复。

## 目录与边界

```text
.
├── apps/
│   ├── zsh/
│   │   ├── manifest.toml
│   │   ├── shared/{profile,interactive,modules}/
│   │   └── platform/{darwin,linux}/
│   ├── vim/vimrc
│   ├── git/gitconfig
│   ├── npm/npmrc
│   ├── ssh/config
│   └── gh/config.yml
├── private/
│   └── {zsh,vim,git,npm,ssh}/
└── scripts/
    ├── apply-dotfiles.zsh
    ├── backup-dotfiles.zsh
    ├── publish-dotfiles.zsh
    ├── restore-dotfiles.zsh
    ├── dotfiles-common.zsh
    └── managed-targets.zsh
```

- `apps/<app>/` 是进入 Git、可跨设备同步的 shared 源码。这里不能放 token、身份、机器名、
  跳板、私钥路径或本机代理。
- `private/<app>/` 是本机明文源码。整个目录被 `.gitignore` 忽略；脚本会把目录权限
  规范为 `700`、文件权限规范为 `600`。private 文件不存在时会静默跳过，首次部署不需要
  先创建私有配置。
- 生成后的目标是自包含的纯文本。Shell、Vim、Git、npm、SSH 和 gh 运行时不依赖仓库路径，
  所以仓库可以移动或卸载而不影响已经部署的配置。
- `.config/gh/hosts.yml` 是 GitHub CLI 的本机认证状态，明确不进入 Git、备份或部署目标。
  tmux、Karabiner、iTerm plist、窗口状态和应用数据库也不在本轮管理范围内。

## 目标注册表

`scripts/managed-targets.zsh` 是唯一的目标注册表，也是备份/恢复使用的唯一目标来源。
每条记录声明：

1. HOME 中的相对路径；
2. 内置 renderer；
3. 支持的平台（`darwin`、`linux`）；
4. 是否进入备份；
5. 生成目标的权限。

当前目标为：`.zshrc`、`.zprofile`、`.zimrc`、`.vimrc`、`.gitconfig`、`.npmrc`、
`.ssh/config` 和 `.config/gh/config.yml`。不创建当前不存在的目标，也不再维护旧的
TOML 注册表、根部模板或任何迁移 shim。

查看当前平台解析出的目标列表：

```zsh
zsh scripts/managed-targets.zsh
```

## 部署、检查与差异

首次部署时先把仓库放到不会被 HOME 目标覆盖的位置，再执行 apply：

```zsh
git clone YOUR_REPOSITORY_URL ~/Workspace/dotfile
cd ~/Workspace/dotfile
zsh scripts/apply-dotfiles.zsh
exec zsh -l
```

在仓库根目录执行：

```zsh
# 渲染并原子写入当前 HOME
zsh scripts/apply-dotfiles.zsh

# 只看计划，不写入
zsh scripts/apply-dotfiles.zsh --dry-run

# 检查内容和权限是否已经一致
zsh scripts/apply-dotfiles.zsh --check

# 查看 unified diff（不会写入）
zsh scripts/apply-dotfiles.zsh --diff
```

脚本会根据 `uname` 自动识别 macOS/Linux；也可以显式指定平台或临时 source/HOME：

```zsh
zsh scripts/apply-dotfiles.zsh \
  --platform linux \
  --source "$PWD" \
  --home "$HOME"
```

写入前脚本会把所有目标渲染到临时 staging，再逐个在目标父目录中使用临时文件和 `mv`
原子替换；父目录如果是符号链接会拒绝写入。`--check` 同时检查注册表声明的权限：含有
本机私有内容的 `.zshrc`、`.zprofile`、`.gitconfig`、`.npmrc` 和 SSH 配置默认是 `600`。

### Zsh 装配顺序和平台边界

`apps/zsh/manifest.toml` 是 Zsh 的唯一加载顺序来源。对 `.zprofile` 和 `.zshrc`，脚本
严格按以下顺序拼接：

```text
shared → 当前平台 fragment → private（存在时）
```

因此 private 可以追加 alias/function/environment，也可以有意覆盖 shared 定义。值得跨
设备同步的片段请手动从 `private/zsh/` 移到 `apps/zsh/`，再删除 private 原片段；脚本不做
自动 promote，也不保留重复兼容层。

Homebrew、`pmset` 等 macOS 内容只在 `platform/darwin/` 加载；Linux 不会加载这些片段，
也不会凭空创建不存在的 Linux 配置。代理地址、远端连接信息、网关 token 和本机管理命令
只放在 ignored `private/zsh/`。

### 快速提交并推送

本机先使用 `gh auth login` 登录 GitHub，然后在仓库的 `main` branch 上执行：

```zsh
zsh scripts/publish-dotfiles.zsh
```

脚本等价于对本仓库执行 `git add .`、使用固定消息 `[updated] dotfiles` 创建
commit，再推送到 `origin main`。没有修改时会直接退出；`private/` 继续由 Git ignore，
不会进入 commit。脚本不会自动 pull、rebase 或 force push，远端存在新提交时会正常拒绝推送。

### Vim Option 键

`apps/vim/vimrc` 保留经过真实 Esc 前缀序列验证的映射：在 Insert 和 Normal 模式下，
Option+Left/Right、Option+Backspace、Option+Fn+Backspace 都可用。`private/vim/vimrc`
只用于本机覆盖。

## 备份与恢复

备份脚本与 apply 使用同一份注册表：

```zsh
zsh scripts/backup-dotfiles.zsh
```

也可以指定临时 HOME/source 或输出目录：

```zsh
zsh scripts/backup-dotfiles.zsh \
  --home "$HOME" \
  --source "$PWD" \
  --output-dir "$HOME/.local/state/dotfiles-backups"
```

归档固定包含两个前缀：

- `home/`：当前平台注册且实际存在的 HOME 目标；
- `private/`：仓库中被忽略的完整 private 源码树（即使为空也保留前缀）。

归档和 `.sha256` 校验文件均为 `600`。恢复只接受这种新格式，并在写回前执行 SHA-256
校验、tar 完整读取、成员类型和路径安全检查、完整 staging 以及交互确认：

```zsh
zsh scripts/restore-dotfiles.zsh \
  "$HOME/.local/state/dotfiles-backups/dotfiles-YYYYMMDD-HHMMSS.tar.gz"

# 自动化场景显式跳过确认
zsh scripts/restore-dotfiles.zsh --yes \
  --source "$PWD" --home "$HOME" \
  "$HOME/.local/state/dotfiles-backups/dotfiles-YYYYMMDD-HHMMSS.tar.gz"
```

恢复会先删除当前注册目标，再完整替换仓库 `private/`，所以随后再次执行 apply 不会丢失
私有内容。旧工具归档和旧生成入口不属于兼容接口；迁移前应先生成一次上述
新格式备份作为回退点。

## 临时 HOME 验证

任何真实 HOME 变更前，建议使用临时 source/HOME：

```zsh
tmp_home_darwin="$(mktemp -d)"
tmp_home_linux="$(mktemp -d)"
zsh scripts/apply-dotfiles.zsh --source "$PWD" --home "$tmp_home_darwin" --platform darwin
zsh scripts/apply-dotfiles.zsh --source "$PWD" --home "$tmp_home_linux" --platform linux
zsh scripts/apply-dotfiles.zsh --source "$PWD" --home "$tmp_home_darwin" --platform darwin --check
zsh scripts/apply-dotfiles.zsh --source "$PWD" --home "$tmp_home_linux" --platform linux --check
for tmp_home in "$tmp_home_darwin" "$tmp_home_linux"; do
  zsh -n "$tmp_home/.zshrc" "$tmp_home/.zprofile"
  vim -Nu "$tmp_home/.vimrc" -n -es +'qa!'
  git config --file "$tmp_home/.gitconfig" --list >/dev/null
  ssh -G -F "$tmp_home/.ssh/config" mine >/dev/null
done
```

检查 `git status` 时，`private/` 的修改不应出现；凭据只应存在于 ignored private 源或临时
HOME 的有效目标中，不应进入 tracked `apps/`。
