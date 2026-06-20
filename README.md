# Cabbage Switch

PowerShell helper for moving Codex Desktop history between Codex providers. History-only sync is the default; full provider switching through CC Switch is opt-in.

## Goal

Codex Desktop groups conversation history by `model_provider`. If you only change `~/.codex/config.toml`, the desktop sidebar can look empty after switching providers: the history still exists, but its local `model_provider` metadata points at a different bucket.

Cabbage Switch fixes that by rewriting the local `model_provider` label in both history stores:

- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/state_*.sqlite`, especially `threads.model_provider`

It works with any number of providers. It inspects your CC Switch Codex providers, shows you a command for each, and runs that command on demand. There are no hardcoded `codex-api` / `codex-openai` command names.

For the implementation details, see [How Cabbage Switch Works](docs/how-it-works.md).

## Requirements

- Windows PowerShell or PowerShell 7
- Python 3 available as `python` or `py`
- Codex Desktop installed and already used at least once
- CC Switch installed and configured with Codex providers (one or more)

No API keys are stored in this repository or in the installed helper script.

## One-Line Install

Run this in PowerShell:

```powershell
irm https://raw.githubusercontent.com/4sa1ary9/cabbage-switch/main/scripts/install.ps1 | iex
```

Then reload the current shell:

```powershell
. $PROFILE
```

Or simply open a new PowerShell window.

## Install From A Clone

```powershell
git clone git@github.com:4sa1ary9/cabbage-switch.git
cd cabbage-switch
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

PowerShell 7 works too:

```powershell
pwsh -File .\scripts\install.ps1
```

The installer copies `src/CabbageSwitch.ps1` to:

```text
~\.cabbage-switch\CabbageSwitch.ps1
```

It also adds a small managed block to your PowerShell profile so the commands are loaded automatically.

## Common Commands

First, see what Cabbage Switch detected on this machine:

```powershell
cabbage-switch
# short alias:
cswitch
```

This prints each Codex provider found in CC Switch and the command to move history into it, for example:

```text
Detected Codex providers:
  id         name                   history_provider
  default    OpenAI                 openai
  d7486227   my api proxy           tec-do   [current]

Move active history to a provider bucket (history only, the default):
  cabbage-switch default
  cabbage-switch tec-do
```

Then run the command for the provider you want history moved to:

```powershell
cabbage-switch default
cabbage-switch tec-do
```

You can use the provider id, its display name, or its `model_provider` value.

Include archived Codex threads as well:

```powershell
cabbage-switch tec-do -IncludeArchived
```

Switch the active provider through CC Switch and then sync history:

```powershell
cabbage-switch tec-do -SwitchProvider
```

Inspect current detection and history state:

```powershell
Show-CabbageSwitchStatus
```

Short alias:

```powershell
cs-status
```

## How Provider Detection Works

Cabbage Switch lists every Codex provider it finds in:

```text
~\.cc-switch\cc-switch.db
```

For each provider it reads the stored Codex config payload and uses its real `model_provider` value as the history bucket. This keeps the tool portable across machines: it does not assume a provider named `api`, `custom`, or any fixed id.

When you pass a provider to `cabbage-switch`, it matches it by id, display name, or `model_provider` value, so you can type whatever is easiest to remember.

## Safety

Before editing `state_*.sqlite`, the script creates a SQLite-consistent backup:

```text
~\.codex\backups\state_5.sqlite.cabbage-switch-YYYYMMDD-HHMMSS.bak
```

JSONL files are updated in place and their timestamps are restored afterward.

If Codex Desktop is already open, the sync can still update the index, but you usually need to fully exit and reopen Codex Desktop before the sidebar refreshes. Closing only the window may leave Codex running in the tray.

## Troubleshooting

If history still does not appear:

1. Run `cs-status` and check that `state.sqlite` and `jsonl` counts match the provider bucket you expect.
2. Fully exit Codex Desktop from the tray or Task Manager.
3. Reopen Codex Desktop.
4. Run `cabbage-switch <provider>` again for the bucket you want history in.

If a provider is not listed by `cabbage-switch`, open CC Switch once and confirm it is a Codex provider. Only Codex providers appear.

If some JSONL files report `Locked` in the summary, Codex Desktop was still running and holding them open. Fully exit Codex Desktop (tray Quit, or end the `Codex` processes in Task Manager) and rerun the same command. Already-moved files are skipped on rerun; only the locked ones update.

## Project Layout

```text
src/CabbageSwitch.ps1      Core PowerShell functions
scripts/install.ps1        One-step installer
examples/basic-usage.ps1   Daily usage examples
docs/how-it-works.md       History and provider switching internals
docs/restore.md            Restore notes
```
