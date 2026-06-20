# Cabbage Switch Genericization Design

## Status
Draft — awaiting user approval

## Problem Statement

The current Cabbage Switch project is tightly coupled to the author's specific environment:

- **Hardcoded command names**: `codex-api`, `codex-openai`, `codex-default`
- **Hardcoded provider detection**: assumes only two providers (official OpenAI and one API/proxy)
- **Hardcoded CC Switch integration**: assumes CC Switch is installed and configured in a specific way

This makes the project difficult for others to adopt. Users with different provider names, multiple proxies, or without CC Switch cannot easily use the tool.

## Goals

1. **Genericize command names**: allow users to define their own command-to-provider mappings
2. **Support multiple providers**: handle arbitrary number of providers, not just two
3. **Decouple from CC Switch**: make CC Switch integration optional, not required
4. **Maintain backward compatibility**: existing `codex-api` / `codex-openai` commands continue to work
5. **Simplify adoption**: new users can configure the tool without understanding internal logic

## Non-Goals

- Rewrite the entire project from scratch
- Remove existing CC Switch integration (make it optional instead)
- Change the core history sync logic (SQLite/JSONL updates)

## Design Overview

### Configuration File

Introduce a configuration file at `~/.cabbage-switch/config.json`:

```json
{
  "providers": {
    "openai": {
      "historyProvider": "openai",
      "ccSwitchProviderId": "default",
      "description": "Official OpenAI login"
    },
    "proxy1": {
      "historyProvider": "tec-do",
      "ccSwitchProviderId": "my-proxy",
      "description": "My first proxy"
    },
    "proxy2": {
      "historyProvider": "custom",
      "ccSwitchProviderId": "another-proxy",
      "description": "Another proxy"
    }
  },
  "commands": {
    "codex-openai": "openai",
    "codex-proxy1": "proxy1",
    "codex-proxy2": "proxy2"
  },
  "settings": {
    "autoDetectProviders": true,
    "requireCcSwitch": false
  }
}
```

### New Generic Commands

Add a new generic command that works with any provider:

```powershell
# Switch history to a specific provider by name
Switch-CodexHistory -Provider "tec-do"

# Or using the generic command
Set-CodexHistoryProvider -Provider "tec-do"
```

### Backward Compatibility

Existing commands (`codex-api`, `codex-openai`) will:
1. Check if configuration exists
2. If yes, use the configured mapping
3. If no, fall back to existing auto-detection logic

### Provider Detection (Refactored)

The existing auto-detection logic will be preserved but moved to a fallback path:

```powershell
function Resolve-CabbageHistoryProvider {
    param([string] $ProviderId)
    
    # 1. Check configuration first
    $configured = Get-ConfiguredProvider $ProviderId
    if ($configured) { return $configured.historyProvider }
    
    # 2. Fall back to existing auto-detection
    return Resolve-CabbageHistoryProviderLegacy $ProviderId
}
```

## Detailed Design

### Configuration Loading

```powershell
function Get-CabbageConfig {
    $configPath = Join-Path (Get-CabbageSwitchHome) 'config.json'
    if (Test-Path $configPath) {
        return Get-Content $configPath | ConvertFrom-Json
    }
    return $null
}
```

### Command Generation (Optional)

If configuration exists, dynamically generate commands:

```powershell
function Register-CabbageCommands {
    $config = Get-CabbageConfig
    if ($config -and $config.commands) {
        foreach ($command in $config.commands.PSObject.Properties) {
            $commandName = $command.Name
            $providerId = $command.Value
            
            # Create a function dynamically
            $script = @"
function $commandName {
    [CmdletBinding(SupportsShouldProcess = `$true)]
    param([switch] `$SwitchProvider, [switch] `$IncludeArchived)
    Z_switch '$providerId' -SwitchProvider:`$SwitchProvider -IncludeArchived:`$IncludeArchived -WhatIf:`$WhatIfPreference
}
"@
            Invoke-Expression $script
        }
    }
}
```

### Core Changes to Existing Functions

#### `Resolve-CabbageCodexProviderSwitchId`

Add configuration lookup before existing logic:

```powershell
function Resolve-CabbageCodexProviderSwitchId {
    param([string] $ProviderId)
    
    # Check configuration first
    $config = Get-CabbageConfig
    if ($config -and $config.providers -and $config.providers.$ProviderId) {
        return $config.providers.$ProviderId.ccSwitchProviderId
    }
    
    # Fall back to existing logic
    # ... (existing code)
}
```

#### `Resolve-CabbageHistoryProvider`

Same pattern — check configuration first, then fall back.

#### `Z_switch`

No changes needed — it already accepts arbitrary provider IDs.

### New Functions

#### `Switch-CodexHistory`

```powershell
function Switch-CodexHistory {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Provider,
        
        [switch] $IncludeArchived
    )
    
    # Validate provider exists in configuration or can be resolved
    $historyProvider = Resolve-CabbageHistoryProvider $Provider
    
    # Sync history
    Sync-CodexHistoryProvider -ModelProvider $historyProvider -IncludeArchived:$IncludeArchived
}
```

## Migration Path for New Users

### Step 1: Install

```powershell
git clone <repo>
cd cabbage-switch
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

### Step 2: Configure

Create `~/.cabbage-switch/config.json`:

```json
{
  "providers": {
    "official": {
      "historyProvider": "openai",
      "ccSwitchProviderId": "default"
    },
    "my-proxy": {
      "historyProvider": "tec-do",
      "ccSwitchProviderId": "proxy1"
    }
  },
  "commands": {
    "codex-official": "official",
    "codex-proxy": "my-proxy"
  }
}
```

### Step 3: Use

```powershell
# Use auto-generated commands
codex-official
codex-proxy

# Or use the generic command
Switch-CodexHistory -Provider "tec-do"
```

## Error Handling

- **Configuration not found**: fall back to existing auto-detection
- **Provider not found in configuration**: throw error with available providers list
- **Invalid configuration**: validate on load, throw descriptive error

## Testing Strategy

1. **Backward compatibility**: verify `codex-api` and `codex-openai` still work without configuration
2. **Configuration loading**: verify config is loaded and used correctly
3. **Command generation**: verify dynamic commands are created and work
4. **Generic command**: verify `Switch-CodexHistory` works with any provider
5. **Error cases**: verify graceful handling of missing/invalid configuration

## Open Questions

1. Should we provide a CLI wizard to generate the initial configuration?
2. Should the configuration be JSON, YAML, or TOML?
3. Should we support environment variables for provider secrets (if any)?
4. How should we handle configuration schema versioning?

## References

- `src/CabbageSwitch.ps1`: existing implementation
- `docs/how-it-works.md`: existing architecture
- `README.md`: existing user documentation
