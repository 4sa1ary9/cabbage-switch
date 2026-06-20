# Cabbage Switch

PowerShell helpers for switching Codex Desktop history between Codex providers. Provider switching through CC Switch is still available, but history-only sync is the default.

## Goal

CC Switch can switch Codex between an official OpenAI login provider and an API/proxy provider, but Codex Desktop history is also indexed locally. If only `~/.codex/config.toml` changes, the desktop sidebar may appear empty after switching providers.

Cabbage Switch solves that by synchronizing both local history stores:

- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/state_*.sqlite`, especially `threads.model_provider`

The default commands only move history metadata:

- `openai`: Codex official login / GPT Plus account
- the API/proxy provider's actual `model_provider` value, such as `tec-do` or `custom`

If you also want Cabbage Switch to switch the active provider through CC Switch, pass `-SwitchProvider` explicitly.

For the implementation details, see [How Cabbage Switch Works](docs/how-it-works.md).

## Requirements

- Windows PowerShell or PowerShell 7
- Python 3 available as `python` or `py`
- Codex Desktop installed and already used at least once
- CC Switch installed and configured with Codex providers
- One official Codex provider, usually `default`
- One API/proxy provider in CC Switch

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

Move active desktop history to the API/proxy provider's actual Codex `model_provider`:

```powershell
codex-api
```

Move active desktop history to the official OpenAI login provider:

```powershell
codex-openai
```

Include archived Codex threads as well:

```powershell
codex-api -IncludeArchived
codex-openai -IncludeArchived
```

Switch the active provider through CC Switch and then sync history:

```powershell
codex-api -SwitchProvider
codex-openai -SwitchProvider
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

For official OpenAI login, Cabbage Switch uses CC Switch provider id:

```text
default
```

For the API/proxy provider, it reads:

```text
~\.cc-switch\cc-switch.db
```

It chooses:

1. the current non-`default` Codex provider if one is active;
2. otherwise a non-`default` provider whose id/name looks like `api`, `custom`, `proxy`, `中转`, or `转发`;
3. otherwise the first non-`default` Codex provider.

For API/proxy history, Cabbage Switch reads that provider's Codex config payload and uses its actual `model_provider` value. This keeps the script portable across computers where CC Switch generated a different provider id or a custom provider name.

## Safety

Before editing `state_*.sqlite`, the script creates a SQLite-consistent backup:

```text
~\.codex\backups\state_5.sqlite.cabbage-switch-YYYYMMDD-HHMMSS.bak
```

JSONL files are updated in place and their timestamps are restored afterward.

If Codex Desktop is already open, the sync can still update the index, but you usually need to fully exit and reopen Codex Desktop before the sidebar refreshes. Closing only the window may leave Codex running in the tray.

## Troubleshooting

If history still does not appear:

1. Run `cs-status` and check that `state.sqlite` and `jsonl` counts match `CodexConfig` or `ApiHistoryProvider`.
2. Fully exit Codex Desktop from the tray or Task Manager.
3. Reopen Codex Desktop.
4. Run `codex-api` or `codex-openai` again.

If the API provider is not detected, open CC Switch once and confirm Codex has a non-default API/proxy provider configured.

## Project Layout

```text
src/CabbageSwitch.ps1      Core PowerShell functions
scripts/install.ps1        One-step installer
examples/basic-usage.ps1   Daily usage examples
docs/how-it-works.md       History and provider switching internals
docs/restore.md            Restore notes
```
