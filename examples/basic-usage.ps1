# Example usage after running scripts/install.ps1.

# Show detected Codex/CC Switch paths, providers, and history buckets.
Show-CabbageSwitchStatus

# List every Codex provider and the command to move history into it.
cabbage-switch
# short alias:
c-switch

# Move active desktop history to a provider bucket.
# <provider> can be the provider id, display name, or model_provider value.
cabbage-switch default
cabbage-switch tec-do

# If you also want to switch the active provider through CC Switch, opt in explicitly.
cabbage-switch tec-do -SwitchProvider

# Include archived threads when you intentionally want old archived history moved too.
cabbage-switch tec-do -IncludeArchived
cabbage-switch default -IncludeArchived
