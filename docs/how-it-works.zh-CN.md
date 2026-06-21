# Cabbage Switch 工作原理

本文档说明 Cabbage Switch 控制的两套机制:

- 仅历史切换(history-only switching),这是默认行为
- 通过 CC Switch 切换 provider,只有在传入 `-SwitchProvider` 时才会发生

## 问题所在

Codex Desktop 把会话历史存在本地,并按 `model_provider` 分组。只切换 `~\.codex\config.toml` 改的是 Codex 新会话用哪个 provider,但不会把已有历史搬到 Codex Desktop 当前显示的那个 provider 桶里。

这就是切换 provider 后侧边栏看起来是空的原因:历史还在,只是它的本地 `model_provider` 元数据指向了另一个 provider。

Cabbage Switch 修改本地元数据,让 Codex Desktop 能在目标 provider 下看到历史。

## 仅历史切换

默认命令只改历史元数据:

```powershell
cabbage-switch <provider>
```

它不会调用 `cc-switch.exe`,不会改 CC Switch 的当前 provider,也不会重写 `~\.codex\config.toml`。

`<provider>` 可以是 CC Switch 里的任意 Codex provider。你可以按 id、显示名或 `model_provider` 值匹配。要精确查看本机有哪些,运行不带参数的 `cabbage-switch`:它会列出检测到的每个 provider 及其对应命令。

流程:

```text
cabbage-switch <provider>
  -> Z_switch
    -> Resolve-CabbageCodexProviderSwitchId
    -> Resolve-CabbageHistoryProvider
    -> Sync-CodexHistoryProvider
      -> Sync-CabbageCodexStateProvider
      -> Sync-CabbageCodexJsonlHistoryProvider
```

`Resolve-CabbageHistoryProvider` 返回所选 provider 的目标 `model_provider`。官方 OpenAI 登录 provider 对应 `openai`。API/proxy provider 则用其真实的 Codex `model_provider`,该值从 `~\.cc-switch\cc-switch.db` 存储的配置 payload 中读取。这很重要,因为 provider 可能叫 `tec-do`、`custom` 或别的名字。

如果读不到该配置,Cabbage Switch 会回退到当前 Codex 配置(当它是 custom-like 时),最后才回退到 `custom`。

## JSONL 历史更新

Codex 会话日志位于:

```text
~\.codex\sessions\**\*.jsonl
```

传入 `-IncludeArchived` 时,Cabbage Switch 还会扫描:

```text
~\.codex\archived_sessions\**\*.jsonl
```

每个 JSONL 文件第一行是 `session_meta` 记录。该行包含 `payload.model_provider`,也就是 Codex Desktop 给会话分组用的 provider 桶。

Cabbage Switch 会:

1. 读取第一行。
2. 按 JSON 解析。
3. 确认它是 `session_meta` 记录。
4. 把 `payload.model_provider` 设为目标 provider。
5. 把第一行写回,保留文件其余内容。
6. 恢复文件的创建、修改、访问时间戳。

这种重写支持长度不同的 provider 名,比如从 `custom` 改到 `tec-do`。

### 被 Codex Desktop 锁定的文件

Codex Desktop 运行时,会持有它正在写入的会话文件的打开句柄。Cabbage Switch 无法重写这些文件,`[System.IO.File]::ReadAllText` 会抛出"文件正由另一进程使用"的错误。

Cabbage Switch 不会把这些混进通用错误计数,而是单独上报:

- 每个被锁文件打印一行简短提示:`Locked by Codex (still running): <path>`
- 摘要对象在 `Errors` 之外新增 `Locked` 计数
- 当 `Locked` 非零时,会输出一段黄色提示块,提醒用户完全退出 Codex Desktop 后重跑同一命令

本次运行不会搬动被锁文件。更新是幂等的,所以退出 Codex 后重跑只会动之前被锁的那些文件。

## SQLite 历史索引更新

Codex Desktop 还在本地 SQLite 数据库中维护一份线程的索引视图:

```text
~\.codex\state_*.sqlite
```

Cabbage Switch 选择最新的、包含 `threads` 表的 `state_*.sqlite` 文件。

对于普通活跃历史,它只更新未归档的行:

```sql
UPDATE threads
SET model_provider = ?
WHERE archived = 0
  AND (model_provider IS NULL OR model_provider <> ?)
```

带 `-IncludeArchived` 时,它更新所有 provider 不同的行:

```sql
UPDATE threads
SET model_provider = ?
WHERE model_provider IS NULL OR model_provider <> ?
```

任何 SQLite 写入前,Cabbage Switch 都会在以下位置创建一份 SQLite 一致性备份:

```text
~\.codex\backups\
```

备份使用 Python 内置的 `sqlite3` backup API,而非直接拷贝文件。

## 通过 CC Switch 切换 provider

provider 切换是可选的:

```powershell
cabbage-switch <provider> -SwitchProvider
```

这条路径会同时改当前 provider 配置和本地历史元数据。

流程:

```text
cabbage-switch <provider> -SwitchProvider
  -> 解析目标 CC Switch provider id
  -> 调用 cc-switch.exe
  -> 如有需要,从 CC Switch provider payload 写入 Codex 配置
  -> 更新 CC Switch 的 current-provider 状态
  -> 同步历史元数据
```

传给 `cabbage-switch` 的 provider id 会按 id、显示名或 `model_provider` 值与 CC Switch provider 匹配,所以同一 `<provider>` 参数在任何机器上都能选对 CC Switch provider。解析出 id 后,Cabbage Switch 调用:

```powershell
cc-switch.exe -a codex provider switch <provider-id>
```

然后确保本地文件与该 provider 一致。

## Codex 配置更新

使用 `-SwitchProvider` 时,Cabbage Switch 从 CC Switch 读取目标 provider 存储的 Codex 配置:

```text
~\.cc-switch\cc-switch.db
providers.settings_config
```

它把该配置写入:

```text
~\.codex\config.toml
```

如果已有配置,会先备份:

```text
~\.codex\backups\config.toml.cabbage-switch-YYYYMMDD-HHMMSS.bak
```

然后 Cabbage Switch 校验 `~\.codex\config.toml` 指向期望的 provider,之后才同步历史。

## CC Switch 状态更新

`-SwitchProvider` 路径还会让 CC Switch 自身状态保持一致。

它会更新:

- `~\.cc-switch\cc-switch.db`,把所选 Codex provider 的 `is_current` 标志置位
- `~\.cc-switch\settings.json`,设置 `currentProviderCodex`

写入前会备份该 JSON 设置文件。

## 安全模型

Cabbage Switch 刻意把默认路径收窄:

- 默认命令只搬历史元数据
- 改当前 provider 配置前必须传 `-SwitchProvider`
- SQLite 写入会创建备份
- JSONL 写入会保留时间戳
- `-WhatIf` 可预览历史同步和 provider 切换两种操作
- 除非传 `-IncludeArchived`,否则不动归档会话

如果 Codex Desktop 正在运行,同步仍能更新文件,但侧边栏可能不会刷新,直到你从托盘或任务管理器完全退出 Codex Desktop 并重新打开。
