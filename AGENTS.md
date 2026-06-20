# Repository Guidelines

## Project Structure & Module Organization

Cabbage Switch is a small Windows PowerShell utility. Runtime code lives in `src/CabbageSwitch.ps1`. The installer is `scripts/install.ps1`, examples live in `examples/basic-usage.ps1`, and supporting docs live in `docs/`. Start with `docs/agent-handoff.md` for maintainer context and `docs/how-it-works.md` for the history/provider switching model. There is no build output directory, asset pipeline, or packaged test suite.

## Build, Test, and Development Commands

- `powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; Resolve-CabbageHistoryProvider api; Resolve-CabbageHistoryProvider default"`: load the script and verify provider resolution.
- `powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; cabbage-switch default -WhatIf"`: dry-run a history-only sync for the `default` provider.
- `powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; cabbage-switch default -SwitchProvider -WhatIf"`: dry-run the opt-in CC Switch provider path.
- `powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\src\CabbageSwitch.ps1'; cabbage-switch"`: list detected providers and the command for each.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1`: install the local clone into `~\.cabbage-switch\`.
- `git diff --check`: check for whitespace problems before committing.

## Coding Style & Naming Conventions

Use PowerShell functions with the existing `Cabbage` prefix for internal helpers, for example `Get-CabbageCodexHome`. Public commands use a generic `cabbage-switch <provider>` form (alias `c-switch`) and `cs-status` / `Show-CabbageSwitchStatus`; there are no hardcoded `codex-api` / `codex-openai` command names. Keep `Set-StrictMode -Version 3.0` compatibility. Prefer explicit paths with `Join-Path`, preserve UTF-8 without BOM where the script writes files, and keep comments sparse and practical.

## Testing Guidelines

There is no formal test framework. Treat `-WhatIf` as the first safety check for any history or provider change. Verify both default history-only behavior and `-SwitchProvider` behavior. If runtime behavior changes, install from the clone and compare `Get-FileHash .\src\CabbageSwitch.ps1, "$HOME\.cabbage-switch\CabbageSwitch.ps1"`.

## Commit & Pull Request Guidelines

History uses concise, imperative commit messages such as `Default to history-only Codex switching` and `docs: explain switching internals`. Keep commits focused. PRs should describe the behavior change, list verification commands run, and call out any migration or safety implications.

## Security & Configuration Tips

Default commands must remain history-only. Only `-SwitchProvider` may call `cc-switch.exe`, update `~\.cc-switch\`, or rewrite `~\.codex\config.toml`. SQLite writes must create backups under `~\.codex\backups\`; JSONL updates must preserve timestamps. Never commit API keys, local provider secrets, or user history files.

# Karpathy Guidelines

Behavioral guidelines to reduce common LLM coding mistakes, derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarif
