# Dotfiles

个人 Shell 配置，使用 chezmoi 生成并部署标准 dotfiles。

## 架构

```text
.
├── shell/
│   └── zsh/
│       ├── manifest.toml
│       ├── settings.zsh
│       ├── lib/
│       ├── plugins/
│       └── themes/
├── dot_zprofile.tmpl
├── dot_zshrc.tmpl
├── dot_zimrc.tmpl
├── .chezmoi.toml.tmpl
└── scripts/
```

`shell/zsh` 是唯一需要日常维护的领域目录：

- `manifest.toml` 声明 profile、交互式模块、插件和主题的装配顺序。
- `settings.zsh` 保存少量跨模块的用户参数。
- `lib` 保存 Zsh 自身行为，例如环境、历史、按键、alias 和 functions。
- `plugins` 保存依赖外部框架或应用的初始化与补全。
- `themes` 只保存提示符主题。

chezmoi 不是一个与 Zsh 并列的配置对象。它只通过仓库根部的元文件和三个
target adapter，把上述源码生成成自包含的 `~/.zprofile`、`~/.zshrc` 和
`~/.zimrc`。HOME 中没有另一份需要维护的 `~/.config/zsh`，Shell 启动时也
不依赖仓库路径；仓库是源码，HOME 中的三个文件是生成物。

根部 `dot_*.tmpl` 是 chezmoi 必需的 target 编码，不放业务实现。日常不直接
编辑它们。它们读取 `manifest.toml` 并用 chezmoi 的 `include` 把模块装配成
目标文件。

## 模块接口

加载拓扑只在 `shell/zsh/manifest.toml` 中修改：

```toml
[profile]
modules = ["environment"]
plugins = ["homebrew", "nvm"]

[interactive]
before = ["environment"]
plugins = ["zim", "nvm", "proxy"]
after = ["history", "options", "keybindings", "aliases", "functions", "listing"]
theme = "personal"
```

插件约定：

- `plugins/<name>/profile.zsh` 在登录阶段装配。
- `plugins/<name>/init.zsh` 在交互阶段装配。
- `plugins/<name>` 可以保存该应用的补全生成逻辑。
- 插件会被直接编译进生成的 dotfile，因此入口顶层不能使用 `return`；缺少命令
  时使用条件块包住实现。

简单 alias/function 不建立插件，分别放在 `lib/aliases.zsh` 和
`lib/functions.zsh`。需要外部程序初始化、hook 或补全时才建立插件。

## 使用

首次在新机器上将仓库 clone 到固定位置，然后让 chezmoi 生成配置并应用：

```zsh
git clone YOUR_REPOSITORY_URL ~/Workspace/dotfile
chezmoi --source "$HOME/Workspace/dotfile" apply --init
exec zsh -l
```

之后的日常流程：

```zsh
cd ~/Workspace/dotfile

# 修改 shell/zsh 下的源码
$EDITOR shell/zsh/lib/aliases.zsh

# 查看最终生成物的变化并部署
chezmoi diff
chezmoi apply
exec zsh -l
```

常用位置：

- 样式：`shell/zsh/themes/personal.zsh`
- alias：`shell/zsh/lib/aliases.zsh`
- functions：`shell/zsh/lib/functions.zsh`
- 历史和按键：`shell/zsh/lib/history.zsh`、`shell/zsh/lib/keybindings.zsh`
- 应用初始化或补全：`shell/zsh/plugins/<name>/init.zsh`

## 备份与恢复

```zsh
./scripts/backup-dotfiles.zsh

./scripts/restore-dotfiles.zsh \
  ~/.local/state/dotfiles-backups/dotfiles-YYYYMMDD-HHMMSS.tar.gz
```

备份和恢复共用 `scripts/managed-targets.zsh`。恢复前会校验 SHA-256、归档成员
路径并完整解压到临时目录，确认后才替换目标。

## 规则

- 不保留兼容 shim、迁移清单或旧目录跳转。
- 目录使用语义名，不使用下划线或数字前缀表达加载顺序。
- `.chezmoiignore` 与 `.gitignore` 随新增源码和运行时文件一起检查。
- token、私钥和机器秘密不进入 Git；需要时使用 chezmoi 的模板与秘密管理能力。
