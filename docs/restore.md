# Restore Notes

Cabbage Switch only changes provider metadata used for Codex Desktop history grouping. It does not edit message content or credentials.

## Restore The SQLite Index

Every SQLite update creates a backup under:

```text
~\.codex\backups\
```

To restore one backup:

1. Fully exit Codex Desktop.
2. Copy the backup over the active state database.

Example:

```powershell
$backup = "$HOME\.codex\backups\state_5.sqlite.cabbage-switch-YYYYMMDD-HHMMSS.bak"
Copy-Item $backup "$HOME\.codex\state_5.sqlite" -Force
Remove-Item "$HOME\.codex\state_5.sqlite-wal","$HOME\.codex\state_5.sqlite-shm" -ErrorAction SilentlyContinue
```

3. Reopen Codex Desktop.

## Re-Sync Instead Of Restoring

Most mistakes can be fixed by syncing the desired bucket again:

```powershell
codex-api -HistoryOnly
codex-openai -HistoryOnly
```

Use `-IncludeArchived` only when archived threads should move too.
