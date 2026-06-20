# Agent Handoff

This document is for an agent taking over maintenance of Cabbage Switch. Start here before editing code.

## Project Purpose

Cabbage Switch is a Windows PowerShell helper for Codex Desktop users who switch between an official OpenAI login provider and a CC Switch API/proxy provider.

Codex Desktop history is grouped by `model_provider` in two local stores:

- `%USERPROFILE%\.codex\sessions/**/*.jsonl`
- `%USERPROFILE%\.codex\state_*.sqlite`, especially `threads.model_provider`

The main product rule is:

**`codex-api` and `codex-openai` default to history-only sync. They must not switch CC Switch or rewrite `~\.codex\config.toml` unless the user passes `-SwitchProvider`.**

## Public Commands

Load the installed script from PowerShell:

```powershell
. "$HOME\.cabbage-switch\CabbageSwitch.ps1"
```

Commands:

- `codex-api`: move active Codex Desktop history to the API/proxy provider's actual Codex `model_provider`, for example `tec-do`.
- `codex-openai`: move active Codex Desktop history to `openai`.
- `codex-default`: alias-style wrapper for `codex-openai`.
- `cs-status` / `Show-CabbageSwitchStatus`: show detected paths, CC Switch providers, and history counts.

Options:

- `-IncludeArchived`: also update archived Codex sessions and archived rows.
- `-SwitchProvider`: opt in to switching the active provider through CC Switch and writing Codex config before syncing history.
- `-HistoryOnly`: backward-compatible no-op. History-only is now the default.
- `-WhatIf`: supported by sync commands. Use this before touching local Codex history during debugging.

## Key Files

- `src/CabbageSwitch.ps1`: all runtime behavior.
- `scripts/install.ps1`: copies `src/CabbageSwitch.ps1` to `~\.cabbage-switch\CabbageSwitch.ps1` and adds the profile loading block.
- `README.md`: user-facing install and command reference.
- `examples/basic-usage.ps1`: short command examples.
- `docs/restore.md`: restore procedure for SQLite backups.
- `docs/agent-handoff.md`: this maintainer handoff.

## Core Flow

The command flow starts at the small wrappers near the bottom of `src/CabbageSwitch.ps1`:

```text
codex-api / codex-openai
  -> Z_switch
    -> Resolve-CabbageCodexProviderSwitchId
    -> Resolve-CabbageHistoryProvider
    -> optionally switch provider when -SwitchProvider is set
    -> Sync-CodexHistoryProvider
      -> Sync-CabbageCodexStateProvider
      -> Sync-CabbageCodexJsonlHistoryProvider
```

Provider resolution:

- Official login maps to CC Switch provider id `default` and history provider `openai`.
- API/proxy maps to a non-`default` CC Switch provider.
- For API/proxy history, do not assume `custom`. Read the provider config payload from `~\.cc-switch\cc-switch.db` and use its real `model_provider`.
- If the provider config cannot be read, the fallback is the current Codex config provider when it is custom-like, then `custom`.

## Safety Rules

Do not weaken these without a very good reason:

- Default commands must be history-only.
- `-SwitchProvider` is the only path that may invoke `cc-switch.exe`, update CC Switch current provider state, or write `~\.codex\config.toml`.
- SQLite updates must create a backup under `~\.codex\backups\`.
- JSONL updates must preserve file timestamps after writing.
- `-WhatIf` must not change CC Switch, Codex config, SQLite, or JSONL files.
- Archived sessions move only when `-IncludeArchived` is set.

## Implementation Notes

SQLite handling uses Python's built-in `sqlite3` module because PowerShell does not include a SQLite client by default. The helper discovers Python through `python` first, then `py`.

`Get-CabbageCodexStateDatabase` scans `state_*.sqlite` files and chooses the newest one that contains a `threads` table.

`Backup-CabbageCodexStateDatabase` uses SQLite's backup API rather than copying the database file directly.

`Set-CabbageJsonlSessionProviderInPlace` rewrites the first JSONL metadata line and preserves the remaining file content. It supports provider names with different lengths, such as `custom` and `tec-do`.

`Repair-CabbageHermesConfig` is a compatibility repair for duplicate `.hermes\config.yaml` `mcp_servers` blocks. It only runs on the `-SwitchProvider` path.

## Local Verification

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; Resolve-CabbageHistoryProvider api; Resolve-CabbageHistoryProvider default"
```

Expected shape:

```text
<actual-api-model-provider>
openai
```

Dry-run the default API history sync:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; codex-api -WhatIf"
```

Dry-run the opt-in provider switch path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; codex-api -SwitchProvider -WhatIf"
```

The second command should include a `What if` line for switching the CC Switch provider, and should not actually change the provider.

Check formatting before committing:

```powershell
git diff --check
```

Git may warn that LF will be replaced by CRLF on Windows. That warning is expected in this repository; actual whitespace errors still matter.

## Install And Smoke Test

After changing runtime behavior, install from the clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Then verify that the installed copy matches the source:

```powershell
Get-FileHash .\src\CabbageSwitch.ps1, "$HOME\.cabbage-switch\CabbageSwitch.ps1" -Algorithm SHA256 | Format-List Path,Hash
```

Finally, load the installed script and smoke-test it:

```powershell
. "$HOME\.cabbage-switch\CabbageSwitch.ps1"
codex-api -WhatIf
codex-api -SwitchProvider -WhatIf
cs-status
```

## Common Failure Modes

History appears missing after switching:

- Run `cs-status`.
- Confirm `CodexConfig`, `ApiHistoryProvider`, `state.sqlite`, and `jsonl` counts agree.
- Fully exit Codex Desktop from the tray or Task Manager, then reopen it.

`codex-api` writes to `custom` even though Codex config uses a custom name:

- Check `Resolve-CabbageHistoryProvider api`.
- Inspect the CC Switch provider config in `~\.cc-switch\cc-switch.db`.
- The API provider config should contain a `model_provider = "..."` line.

PowerShell command is not found:

- Run `. $PROFILE` or open a new PowerShell window.
- Confirm the profile contains the managed `# >>> cabbage-switch >>>` block.
- Re-run `scripts/install.ps1` if needed.

Python not found:

- Install Python 3 or make `python`/`py` available on PATH.
- The script cannot safely read or write SQLite without Python.

## Release Checklist

Before committing:

1. Update `README.md`, `scripts/install.ps1`, and examples when command behavior changes.
2. Run the local verification commands above.
3. If runtime behavior changed, install from the clone and confirm the installed hash matches source.
4. Confirm `git status --short --branch` only contains intentional files.
5. Commit with a behavior-focused message.
