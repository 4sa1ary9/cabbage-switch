# Cabbage Switch

**[English](README.md)** | **简体中文**

PowerShell 辅助工具,用于在 Codex 各 provider 之间搬运 Codex Desktop 的历史会话。默认只搬历史;通过 CC Switch 完整切换 provider 为可选(opt-in)。

## 目标

Codex Desktop 按 `model_provider` 对历史会话分组。如果只改 `~/.codex/config.toml`,切换 provider 后桌面侧边栏会显得是空的:历史其实还在,只是它的本地 `model_provider` 元数据指向了另一个桶。

Cabbage Switch 通过重写两个本地历史存储里的 `model_provider` 标签来解决这个问题:

- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/state_*.sqlite`,尤其是 `threads.model_provider`

它能适配任意数量的 provider:检测你的 CC Switch Codex provider,为每个 provider 给出对应命令,按需执行。没有写死的 `codex-api` / `codex-openai` 命令名。

实现细节见 [Cabbage Switch 工作原理](docs/how-it-works(如何工作).md)。

## 环境要求

- Windows PowerShell 或 PowerShell 7
- Python 3,可通过 `python` 或 `py` 调用
- 已安装 Codex Desktop 并至少使用过一次
- 已安装 CC Switch 并配置了 Codex provider(一个或多个)

本仓库及安装后的辅助脚本中都不存储任何 API key。

## 一行安装

在 PowerShell 中执行:

```powershell
irm https://raw.githubusercontent.com/4sa1ary9/cabbage-switch/main/scripts/install.ps1 | iex
```

然后重新加载当前 shell:

```powershell
. $PROFILE
```

或者直接开一个新的 PowerShell 窗口。

## 从克隆安装

```powershell
git clone git@github.com:4sa1ary9/cabbage-switch.git
cd cabbage-switch
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

PowerShell 7 也可以:

```powershell
pwsh -File .\scripts\install.ps1
```

安装器会把 `src/CabbageSwitch.ps1` 复制到:

```text
~\.cabbage-switch\CabbageSwitch.ps1
```

它还会在你的 PowerShell profile 中加一小段托管块,使命令自动加载。

## 常用命令

先看看本机检测到了哪些 provider:

```powershell
cabbage-switch
# 简写别名:
cswitch
```

这会打印出 CC Switch 里找到的每个 Codex provider 以及把历史搬到该 provider 的命令,例如:

```text
Detected Codex providers:
  id         name                   codex_provider
  default    OpenAI                 openai
  d7486227   my api proxy           tec-do   [current]

Move active history to a provider bucket (history only, the default):
  cabbage-switch default
  cabbage-switch tec-do
```

然后运行你想把历史搬到的那个 provider 的命令:

```powershell
cabbage-switch default
cabbage-switch tec-do
```

你可以用 provider id、显示名,或它的 `model_provider` 值来匹配。

也搬运已归档的 Codex 会话:

```powershell
cabbage-switch tec-do -IncludeArchived
```

通过 CC Switch 切换当前 provider,然后再同步历史:

```powershell
cabbage-switch tec-do -SwitchProvider
```

查看当前检测结果和历史状态:

```powershell
Show-CabbageSwitchStatus
```

简写别名:

```powershell
cs-status
```

## Provider 检测原理

Cabbage Switch 列出它在以下位置找到的所有 Codex provider:

```text
~\.cc-switch\cc-switch.db
```

对每个 provider,它读取存储的 Codex 配置 payload,用其真实的 `model_provider` 值作为历史桶。这让工具能跨机器使用:它不假设 provider 叫 `api`、`custom` 或任何固定 id。

当你向 `cabbage-switch` 传入 provider 时,它会按 id、显示名或 `model_provider` 值进行匹配,所以你输入最容易记住的那个就行。

## 安全

在改写 `state_*.sqlite` 之前,脚本会创建一份 SQLite 一致性备份:

```text
~\.codex\backups\state_5.sqlite.cabbage-switch-YYYYMMDD-HHMMSS.bak
```

JSONL 文件原地更新,之后恢复其时间戳。

如果 Codex Desktop 已经开着,同步仍能更新索引,但通常你需要先完全退出 Codex Desktop 再重开,侧边栏才会刷新。只关窗口可能让 Codex 留在托盘里运行。

## 故障排查

如果历史仍然不显示:

1. 运行 `cs-status`,确认 `state.sqlite` 和 `jsonl` 的数量与你期望的 provider 桶一致。
2. 从托盘或任务管理器完全退出 Codex Desktop。
3. 重新打开 Codex Desktop。
4. 再次运行 `cabbage-switch <provider>`,把历史搬到目标桶。

如果某个 provider 没被 `cabbage-switch` 列出,打开一次 CC Switch 确认它是 Codex provider。只有 Codex provider 会显示。

如果摘要里有 JSONL 文件报告 `Locked`,说明 Codex Desktop 当时还在运行并占着这些文件。完全退出 Codex Desktop(托盘 Quit,或在任务管理器结束 `Codex` 进程),然后重跑同一命令。已搬过的文件会跳过,只有被锁的那些会更新。

## 项目结构

```text
src/CabbageSwitch.ps1         核心 PowerShell 函数
scripts/install.ps1           一步安装器
examples/basic-usage.ps1      日常用法示例
docs/how-it-works(如何工作).md 历史与 provider 切换的内部原理
docs/restore(还原说明).md      还原说明
```

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
