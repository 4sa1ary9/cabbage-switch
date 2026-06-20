# How Cabbage Switch Works

This document explains the two mechanisms Cabbage Switch controls:

- history-only switching, which is the default behavior
- provider switching through CC Switch, which only happens when `-SwitchProvider` is passed

## The problem

Codex Desktop stores conversation history locally, and that history is grouped by `model_provider`. Switching only `~\.codex\config.toml` changes which provider Codex uses for new work, but it does not automatically move existing history into the provider bucket Codex Desktop is currently showing.

That is why the sidebar can look empty after a provider switch: the history still exists, but its local `model_provider` metadata points at a different provider.

Cabbage Switch fixes the local metadata so Codex Desktop can see the history under the intended provider.

## History-only switching

The default commands only change history metadata:

```powershell
codex-api
codex-openai
```

They do not call `cc-switch.exe`, do not change CC Switch's current provider, and do not rewrite `~\.codex\config.toml`.

The flow is:

```text
codex-api / codex-openai
  -> Z_switch
    -> Resolve-CabbageCodexProviderSwitchId
    -> Resolve-CabbageHistoryProvider
    -> Sync-CodexHistoryProvider
      -> Sync-CabbageCodexStateProvider
      -> Sync-CabbageCodexJsonlHistoryProvider
```

`codex-openai` resolves to the history provider `openai`.

`codex-api` resolves to the API/proxy provider's actual Codex `model_provider`. This is important because the provider may be named `tec-do`, `custom`, or something else. Cabbage Switch reads the provider config payload from `~\.cc-switch\cc-switch.db` and parses its `model_provider = "..."` line.

If that config cannot be read, Cabbage Switch falls back to the current Codex config when it is custom-like, then finally to `custom`.

## JSONL history updates

Codex session logs live under:

```text
~\.codex\sessions\**\*.jsonl
```

When `-IncludeArchived` is passed, Cabbage Switch also scans:

```text
~\.codex\archived_sessions\**\*.jsonl
```

Each JSONL file starts with a `session_meta` line. That line contains `payload.model_provider`, which is the provider bucket Codex Desktop uses for the session.

Cabbage Switch:

1. Reads the first line.
2. Parses it as JSON.
3. Confirms it is a `session_meta` record.
4. Sets `payload.model_provider` to the target provider.
5. Writes the first line back and preserves the rest of the file content.
6. Restores the file's creation, write, and access timestamps.

This rewrite supports provider names with different lengths, such as moving from `custom` to `tec-do`.

## SQLite history index updates

Codex Desktop also keeps an indexed view of threads in a local SQLite database:

```text
~\.codex\state_*.sqlite
```

Cabbage Switch chooses the newest `state_*.sqlite` file that contains a `threads` table.

For normal active history, it updates only non-archived rows:

```sql
UPDATE threads
SET model_provider = ?
WHERE archived = 0
  AND (model_provider IS NULL OR model_provider <> ?)
```

With `-IncludeArchived`, it updates all rows whose provider differs:

```sql
UPDATE threads
SET model_provider = ?
WHERE model_provider IS NULL OR model_provider <> ?
```

Before any SQLite write, Cabbage Switch creates a SQLite-consistent backup under:

```text
~\.codex\backups\
```

The backup uses Python's built-in `sqlite3` backup API rather than a raw file copy.

## Provider switching through CC Switch

Provider switching is opt-in:

```powershell
codex-api -SwitchProvider
codex-openai -SwitchProvider
```

This path changes both the active provider configuration and the local history metadata.

The flow is:

```text
codex-api -SwitchProvider / codex-openai -SwitchProvider
  -> resolve target CC Switch provider id
  -> call cc-switch.exe
  -> write Codex config from CC Switch provider payload if needed
  -> update CC Switch current-provider state
  -> sync history metadata
```

For the official OpenAI login provider, the CC Switch provider id is `default`.

For API/proxy providers, Cabbage Switch reads `~\.cc-switch\cc-switch.db` and chooses:

1. the current non-`default` Codex provider
2. otherwise a non-`default` provider whose id or name looks like `api`, `custom`, `proxy`, `中转`, or `转发`
3. otherwise the first non-`default` Codex provider

After resolving the provider id, Cabbage Switch calls:

```powershell
cc-switch.exe -a codex provider switch <provider-id>
```

Then it ensures the local files match that provider.

## Codex config updates

When `-SwitchProvider` is used, Cabbage Switch reads the target provider's stored Codex config from CC Switch:

```text
~\.cc-switch\cc-switch.db
providers.settings_config
```

It writes that config to:

```text
~\.codex\config.toml
```

If an existing config exists, it is backed up first:

```text
~\.codex\backups\config.toml.cabbage-switch-YYYYMMDD-HHMMSS.bak
```

Cabbage Switch then verifies that `~\.codex\config.toml` points at the expected provider before it syncs history.

## CC Switch state updates

The `-SwitchProvider` path also keeps CC Switch's own state aligned.

It updates:

- `~\.cc-switch\cc-switch.db`, setting the selected Codex provider's `is_current` flag
- `~\.cc-switch\settings.json`, setting `currentProviderCodex`

The JSON settings file is backed up before writing.

## Safety model

Cabbage Switch keeps the default path narrow on purpose:

- default commands only move history metadata
- `-SwitchProvider` is required before changing active provider config
- SQLite writes create backups
- JSONL writes preserve timestamps
- `-WhatIf` previews both history sync and provider-switch operations
- archived sessions are left alone unless `-IncludeArchived` is passed

If Codex Desktop is running, the sync can update the files, but the sidebar may not refresh until Codex Desktop is fully exited from the tray or Task Manager and opened again.
