# Example usage after running scripts/install.ps1.

# Show detected Codex/CC Switch paths, providers, and history buckets.
Show-CabbageSwitchStatus

# Switch Codex to the API/proxy provider and sync active desktop history.
codex-api

# Switch Codex back to the official OpenAI login provider and sync active desktop history.
codex-openai

# If you switched provider in the CC Switch GUI, use HistoryOnly to sync only history metadata.
codex-api -HistoryOnly
codex-openai -HistoryOnly

# Include archived threads when you intentionally want old archived history moved too.
codex-api -HistoryOnly -IncludeArchived
codex-openai -HistoryOnly -IncludeArchived
