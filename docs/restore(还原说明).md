# 还原说明

Cabbage Switch 只改 Codex Desktop 历史分组用的 provider 元数据。它不编辑消息内容,也不碰凭据。

## 还原 SQLite 索引

每次 SQLite 更新都会在以下位置创建备份:

```text
~\.codex\backups\
```

还原某个备份:

1. 完全退出 Codex Desktop。
2. 把备份覆盖到当前 state 数据库。

示例:

```powershell
$backup = "$HOME\.codex\backups\state_5.sqlite.cabbage-switch-YYYYMMDD-HHMMSS.bak"
Copy-Item $backup "$HOME\.codex\state_5.sqlite" -Force
Remove-Item "$HOME\.codex\state_5.sqlite-wal","$HOME\.codex\state_5.sqlite-shm" -ErrorAction SilentlyContinue
```

3. 重新打开 Codex Desktop。

## 与其还原,不如重新同步

大多数错误都可以通过再次同步到目标桶来修复:

```powershell
cabbage-switch <provider>
```

只有当你要把归档会话也搬过去时,才使用 `-IncludeArchived`。
