# Repository Guidelines

## Project Structure & Module Organization

Cabbage Switch is a small Windows PowerShell utility. Runtime code lives in `src/CabbageSwitch.ps1`. The installer is `scripts/install.ps1`, examples live in `examples/basic-usage.ps1`, and supporting docs live in `docs/`. Start with `docs/agent-handoff.md` for maintainer context and `docs/how-it-works.md` for the history/provider switching model. There is no build output directory, asset pipeline, or packaged test suite.

## Build, Test, and Development Commands

- `powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; Resolve-CabbageHistoryProvider api; Resolve-CabbageHistoryProvider default"`: load the script and verify provider resolution.
- `powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; codex-api -WhatIf"`: dry-run the default history-only API sync.
- `powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; codex-api -SwitchProvider -WhatIf"`: dry-run the opt-in CC Switch provider path.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1`: install the local clone into `~\.cabbage-switch\`.
- `git diff --check`: check for whitespace problems before committing.

## Coding Style & Naming Conventions

Use PowerShell functions with the existing `Cabbage` prefix for internal helpers, for example `Get-CabbageCodexHome`. Public commands use `codex-*` names. Keep `Set-StrictMode -Version 3.0` compatibility. Prefer explicit paths with `Join-Path`, preserve UTF-8 without BOM where the script writes files, and keep comments sparse and practical.

## Testing Guidelines

There is no formal test framework. Treat `-WhatIf` as the first safety check for any history or provider change. Verify both default history-only behavior and `-SwitchProvider` behavior. If runtime behavior changes, install from the clone and compare `Get-FileHash .\src\CabbageSwitch.ps1, "$HOME\.cabbage-switch\CabbageSwitch.ps1"`.

## Commit & Pull Request Guidelines

History uses concise, imperative commit messages such as `Default to history-only Codex switching` and `docs: explain switching internals`. Keep commits focused. PRs should describe the behavior change, list verification commands run, and call out any migration or safety implications.

## Security & Configuration Tips

Default commands must remain history-only. Only `-SwitchProvider` may call `cc-switch.exe`, update `~\.cc-switch\`, or rewrite `~\.codex\config.toml`. SQLite writes must create backups under `~\.codex\backups\`; JSONL updates must preserve timestamps. Never commit API keys, local provider secrets, or user history files.
