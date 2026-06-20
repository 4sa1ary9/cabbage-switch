# Example usage after running scripts/install.ps1.

# Show detected Codex/CC Switch paths, providers, and history buckets.
Show-CabbageSwitchStatus

# Move active desktop history to the API/proxy provider.
codex-api

# Move active desktop history to the official OpenAI login provider.
codex-openai

# If you also want to switch the active provider through CC Switch, opt in explicitly.
codex-api -SwitchProvider
codex-openai -SwitchProvider

# Include archived threads when you intentionally want old archived history moved too.
codex-api -IncludeArchived
codex-openai -IncludeArchived
