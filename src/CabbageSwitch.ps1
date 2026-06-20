Set-StrictMode -Version 3.0

function Get-CabbageCodexHome {
    if ($env:CODEX_HOME -and (Test-Path -LiteralPath $env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }

    return (Join-Path $HOME '.codex')
}

function Get-CabbageCcSwitchHome {
    return (Join-Path $HOME '.cc-switch')
}

function Get-CabbageCcSwitchExe {
    $knownPath = Join-Path $env:LOCALAPPDATA 'Programs\CC Switch\cc-switch.exe'
    if (Test-Path -LiteralPath $knownPath) {
        return $knownPath
    }

    $command = Get-Command cc-switch -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw 'CC Switch executable was not found. Install CC Switch first, or add cc-switch.exe to PATH.'
}

function Get-CabbagePythonExe {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        return $py.Source
    }

    throw 'Python was not found. Install Python 3 or make python/py available in PATH.'
}

function Invoke-CabbagePythonJson {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Script,

        [string[]] $Arguments = @()
    )

    $python = Get-CabbagePythonExe
    $output = $Script | & $python - @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed with exit code $LASTEXITCODE."
    }

    if (-not $output) {
        return $null
    }

    return ($output | ConvertFrom-Json)
}

function Get-CabbageCodexProviders {
    $dbPath = Join-Path (Get-CabbageCcSwitchHome) 'cc-switch.db'
    if (-not (Test-Path -LiteralPath $dbPath)) {
        return @()
    }

    $script = @'
import json
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    cur = conn.cursor()
    rows = cur.execute("""
        SELECT id, name, category, provider_type, is_current, sort_index
        FROM providers
        WHERE app_type = 'codex'
        ORDER BY sort_index IS NULL, sort_index, name
    """).fetchall()
    print(json.dumps([
        {
            "id": row[0],
            "name": row[1],
            "category": row[2],
            "provider_type": row[3],
            "is_current": bool(row[4]),
            "sort_index": row[5],
        }
        for row in rows
    ], ensure_ascii=False))
finally:
    conn.close()
'@

    $providers = Invoke-CabbagePythonJson -Script $script -Arguments @($dbPath)
    if ($null -eq $providers) {
        return @()
    }

    return @($providers)
}

function Resolve-CabbageCodexApiProviderId {
    $providers = @(Get-CabbageCodexProviders)
    $nonDefault = @($providers | Where-Object { $_.id -ne 'default' })

    $currentNonDefault = @($nonDefault | Where-Object { $_.is_current }) | Select-Object -First 1
    if ($currentNonDefault) {
        return [string] $currentNonDefault.id
    }

    $named = @(
        $nonDefault |
            Where-Object { $_.name -match 'api|custom|proxy|中转|转发' -or $_.id -match 'api|custom|proxy' }
    ) | Select-Object -First 1
    if ($named) {
        return [string] $named.id
    }

    $first = $nonDefault | Select-Object -First 1
    if ($first) {
        return [string] $first.id
    }

    throw 'No non-default Codex provider was found in CC Switch. Create an API/proxy provider in CC Switch first.'
}

function Resolve-CabbageCodexProviderSwitchId {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ProviderId
    )

    $key = $ProviderId.ToLowerInvariant()
    if ($key -in @('default', 'openai', 'oai', 'official')) {
        return 'default'
    }

    if ($key -in @('api', 'custom', 'proxy')) {
        return (Resolve-CabbageCodexApiProviderId)
    }

    $providers = @(Get-CabbageCodexProviders)
    $matched = @(
        $providers |
            Where-Object {
                $_.id -eq $ProviderId -or
                ([string] $_.name).Equals($ProviderId, [System.StringComparison]::OrdinalIgnoreCase)
            }
    ) | Select-Object -First 1
    if ($matched) {
        return [string] $matched.id
    }

    return $ProviderId
}

function Resolve-CabbageHistoryProvider {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ProviderId
    )

    $switchId = Resolve-CabbageCodexProviderSwitchId $ProviderId
    if ($switchId -eq 'default') {
        return 'openai'
    }

    return 'custom'
}

function Get-CabbageCodexStateDatabase {
    $codexHome = Get-CabbageCodexHome
    $candidates = @(
        Get-ChildItem -LiteralPath $codexHome -File -Filter 'state_*.sqlite' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )

    foreach ($candidate in $candidates) {
        $script = @'
import json
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    exists = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='threads'"
    ).fetchone() is not None
    print(json.dumps({"exists": exists}))
finally:
    conn.close()
'@
        try {
            $result = Invoke-CabbagePythonJson -Script $script -Arguments @($candidate.FullName)
            if ($result.exists) {
                return $candidate.FullName
            }
        }
        catch {
            continue
        }
    }

    return $null
}

function Backup-CabbageCodexStateDatabase {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $DatabasePath
    )

    $backupDir = Join-Path (Split-Path -Parent $DatabasePath) 'backups'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $backupDir ("{0}.cabbage-switch-{1}.bak" -f (Split-Path -Leaf $DatabasePath), $timestamp)

    $script = @'
import sqlite3
import sys

source_path = sys.argv[1]
backup_path = sys.argv[2]

source = sqlite3.connect(source_path)
try:
    backup = sqlite3.connect(backup_path)
    try:
        source.backup(backup)
    finally:
        backup.close()
finally:
    source.close()
'@

    Invoke-CabbagePythonJson -Script $script -Arguments @($DatabasePath, $backupPath) | Out-Null
    return $backupPath
}

function Set-CabbageJsonlSessionProviderInPlace {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateSet('openai', 'custom')]
        [string] $ModelProvider
    )

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    try {
        $bytes = [byte[]]::new($stream.Length)
        $read = $stream.Read($bytes, 0, $bytes.Length)
        if ($read -le 0) {
            return $false
        }

        $newlineIndex = [Array]::IndexOf($bytes, [byte][char]"`n")
        if ($newlineIndex -lt 0) {
            $newlineIndex = $read
        }

        $needle = [System.Text.Encoding]::UTF8.GetBytes('"model_provider":"')
        $value = [System.Text.Encoding]::UTF8.GetBytes($ModelProvider)
        $offset = -1

        for ($i = 0; $i -le ($newlineIndex - $needle.Length); $i++) {
            $matches = $true
            for ($j = 0; $j -lt $needle.Length; $j++) {
                if ($bytes[$i + $j] -ne $needle[$j]) {
                    $matches = $false
                    break
                }
            }

            if ($matches) {
                $offset = $i + $needle.Length
                break
            }
        }

        if ($offset -lt 0) {
            return $false
        }

        $endOffset = $offset
        while ($endOffset -lt $newlineIndex -and $bytes[$endOffset] -ne [byte][char]'"') {
            $endOffset++
        }

        if (($endOffset - $offset) -ne $value.Length) {
            throw "Cannot update model_provider in place because the existing value length differs from '$ModelProvider'."
        }

        $stream.Position = $offset
        $stream.Write($value, 0, $value.Length)
        $stream.Flush()
        return $true
    }
    finally {
        $stream.Dispose()
    }
}

function Sync-CabbageCodexJsonlHistoryProvider {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('openai', 'custom')]
        [string] $ModelProvider,

        [switch] $IncludeArchived
    )

    $codexHome = Get-CabbageCodexHome
    $roots = @((Join-Path $codexHome 'sessions'))
    if ($IncludeArchived) {
        $roots += (Join-Path $codexHome 'archived_sessions')
    }

    $scanned = 0
    $changed = 0
    $skipped = 0
    $errors = 0

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.jsonl') {
            $scanned++

            try {
                $item = Get-Item -LiteralPath $file.FullName -ErrorAction Stop
                $creationTimeUtc = $item.CreationTimeUtc
                $lastWriteTimeUtc = $item.LastWriteTimeUtc
                $lastAccessTimeUtc = $item.LastAccessTimeUtc

                $firstLine = Get-Content -LiteralPath $file.FullName -TotalCount 1 -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($firstLine)) {
                    $skipped++
                    continue
                }

                $meta = $firstLine | ConvertFrom-Json -ErrorAction Stop
                if ($meta.type -ne 'session_meta' -or -not $meta.payload) {
                    $skipped++
                    continue
                }

                if ($meta.payload.model_provider -eq $ModelProvider) {
                    $skipped++
                    continue
                }

                if ($PSCmdlet.ShouldProcess($file.FullName, "set model_provider to $ModelProvider")) {
                    $updated = Set-CabbageJsonlSessionProviderInPlace -Path $file.FullName -ModelProvider $ModelProvider
                    if (-not $updated) {
                        $skipped++
                        continue
                    }

                    $item = Get-Item -LiteralPath $file.FullName
                    $item.CreationTimeUtc = $creationTimeUtc
                    $item.LastWriteTimeUtc = $lastWriteTimeUtc
                    $item.LastAccessTimeUtc = $lastAccessTimeUtc
                    $changed++
                }
            }
            catch {
                $errors++
                Write-Warning ("Failed to update {0}: {1}" -f $file.FullName, $_.Exception.Message)
            }
        }
    }

    [pscustomobject]@{
        Store           = 'jsonl'
        ModelProvider   = $ModelProvider
        Scanned         = $scanned
        Changed         = $changed
        Skipped         = $skipped
        Errors          = $errors
        IncludeArchived = [bool] $IncludeArchived
        BackupPath      = $null
    }
}

function Sync-CabbageCodexStateProvider {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('openai', 'custom')]
        [string] $ModelProvider,

        [switch] $IncludeArchived
    )

    $databasePath = Get-CabbageCodexStateDatabase
    if (-not $databasePath) {
        return [pscustomobject]@{
            Store           = 'state.sqlite'
            ModelProvider   = $ModelProvider
            Scanned         = 0
            Changed         = 0
            Skipped         = 0
            Errors          = 0
            IncludeArchived = [bool] $IncludeArchived
            BackupPath      = $null
        }
    }

    $script = @'
import json
import sqlite3
import sys

db_path = sys.argv[1]
model_provider = sys.argv[2]
include_archived = sys.argv[3] == "1"

conn = sqlite3.connect(db_path)
try:
    cur = conn.cursor()
    if include_archived:
        total = cur.execute("SELECT COUNT(*) FROM threads").fetchone()[0]
        changed = cur.execute(
            "SELECT COUNT(*) FROM threads WHERE model_provider <> ?",
            (model_provider,),
        ).fetchone()[0]
        cur.execute(
            "UPDATE threads SET model_provider = ? WHERE model_provider <> ?",
            (model_provider, model_provider),
        )
    else:
        total = cur.execute("SELECT COUNT(*) FROM threads WHERE archived = 0").fetchone()[0]
        changed = cur.execute(
            "SELECT COUNT(*) FROM threads WHERE archived = 0 AND model_provider <> ?",
            (model_provider,),
        ).fetchone()[0]
        cur.execute(
            "UPDATE threads SET model_provider = ? WHERE archived = 0 AND model_provider <> ?",
            (model_provider, model_provider),
        )

    conn.commit()
    print(json.dumps({
        "scanned": total,
        "changed": changed,
        "skipped": total - changed,
    }))
finally:
    conn.close()
'@

    $backupPath = $null
    try {
        if ($PSCmdlet.ShouldProcess($databasePath, "set threads.model_provider to $ModelProvider")) {
            $backupPath = Backup-CabbageCodexStateDatabase $databasePath
            $result = Invoke-CabbagePythonJson -Script $script -Arguments @($databasePath, $ModelProvider, $(if ($IncludeArchived) { '1' } else { '0' }))
            return [pscustomobject]@{
                Store           = 'state.sqlite'
                ModelProvider   = $ModelProvider
                Scanned         = [int] $result.scanned
                Changed         = [int] $result.changed
                Skipped         = [int] $result.skipped
                Errors          = 0
                IncludeArchived = [bool] $IncludeArchived
                BackupPath      = $backupPath
            }
        }
    }
    catch {
        Write-Warning ("Failed to update Codex state database {0}: {1}" -f $databasePath, $_.Exception.Message)
        return [pscustomobject]@{
            Store           = 'state.sqlite'
            ModelProvider   = $ModelProvider
            Scanned         = 0
            Changed         = 0
            Skipped         = 0
            Errors          = 1
            IncludeArchived = [bool] $IncludeArchived
            BackupPath      = $backupPath
        }
    }

    [pscustomobject]@{
        Store           = 'state.sqlite'
        ModelProvider   = $ModelProvider
        Scanned         = 0
        Changed         = 0
        Skipped         = 0
        Errors          = 0
        IncludeArchived = [bool] $IncludeArchived
        BackupPath      = $null
    }
}

function Sync-CodexHistoryProvider {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('openai', 'custom')]
        [string] $ModelProvider,

        [switch] $IncludeArchived
    )

    Sync-CabbageCodexStateProvider -ModelProvider $ModelProvider -IncludeArchived:$IncludeArchived -WhatIf:$WhatIfPreference
    Sync-CabbageCodexJsonlHistoryProvider -ModelProvider $ModelProvider -IncludeArchived:$IncludeArchived -WhatIf:$WhatIfPreference
}

function Get-CodexHistoryProviderSummary {
    param(
        [switch] $IncludeArchived
    )

    $codexHome = Get-CabbageCodexHome
    $roots = @((Join-Path $codexHome 'sessions'))
    if ($IncludeArchived) {
        $roots += (Join-Path $codexHome 'archived_sessions')
    }

    $counts = @{}
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.jsonl') {
            try {
                $firstLine = Get-Content -LiteralPath $file.FullName -TotalCount 1 -ErrorAction Stop
                if (-not $firstLine) {
                    continue
                }

                $meta = $firstLine | ConvertFrom-Json -ErrorAction Stop
                $provider = $meta.payload.model_provider
                if (-not $provider) {
                    $provider = '<missing>'
                }
            }
            catch {
                $provider = '<parse-error>'
            }

            if (-not $counts.ContainsKey($provider)) {
                $counts[$provider] = 0
            }
            $counts[$provider]++
        }
    }

    $counts.GetEnumerator() |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Store         = 'jsonl'
                ModelProvider = $_.Key
                Count         = $_.Value
            }
        }
}

function Get-CodexStateProviderSummary {
    param(
        [switch] $IncludeArchived
    )

    $databasePath = Get-CabbageCodexStateDatabase
    if (-not $databasePath) {
        return @()
    }

    $script = @'
import json
import sqlite3
import sys

db_path = sys.argv[1]
include_archived = sys.argv[2] == "1"
conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    cur = conn.cursor()
    if include_archived:
        rows = cur.execute("""
            SELECT model_provider, archived, COUNT(*)
            FROM threads
            GROUP BY model_provider, archived
            ORDER BY model_provider, archived
        """).fetchall()
    else:
        rows = cur.execute("""
            SELECT model_provider, archived, COUNT(*)
            FROM threads
            WHERE archived = 0
            GROUP BY model_provider, archived
            ORDER BY model_provider, archived
        """).fetchall()
    print(json.dumps([
        {"model_provider": row[0], "archived": bool(row[1]), "count": row[2]}
        for row in rows
    ], ensure_ascii=False))
finally:
    conn.close()
'@

    $rows = Invoke-CabbagePythonJson -Script $script -Arguments @($databasePath, $(if ($IncludeArchived) { '1' } else { '0' }))
    @($rows) | ForEach-Object {
        [pscustomobject]@{
            Store         = 'state.sqlite'
            ModelProvider = $_.model_provider
            Archived      = $_.archived
            Count         = $_.count
        }
    }
}

function Show-CabbageSwitchStatus {
    $configPath = Join-Path (Get-CabbageCodexHome) 'config.toml'
    $configProvider = $null
    if (Test-Path -LiteralPath $configPath) {
        $line = Get-Content -LiteralPath $configPath -TotalCount 1
        if ($line -match 'model_provider\s*=\s*"([^"]+)"') {
            $configProvider = $Matches[1]
        }
    }

    [pscustomobject]@{
        CodexHome       = Get-CabbageCodexHome
        CcSwitchHome    = Get-CabbageCcSwitchHome
        CcSwitchExe     = $(try { Get-CabbageCcSwitchExe } catch { $null })
        CodexConfig     = $configProvider
        StateDatabase   = Get-CabbageCodexStateDatabase
        ApiProviderId   = $(try { Resolve-CabbageCodexApiProviderId } catch { $null })
    }

    Get-CabbageCodexProviders |
        Select-Object id, name, category, provider_type, is_current |
        Format-Table -AutoSize

    Get-CodexStateProviderSummary | Format-Table -AutoSize
    Get-CodexHistoryProviderSummary | Format-Table -AutoSize
}

function Z_switch {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ProviderId,

        [switch] $HistoryOnly,
        [switch] $IncludeArchived
    )

    $switchId = Resolve-CabbageCodexProviderSwitchId $ProviderId
    $historyProvider = Resolve-CabbageHistoryProvider $ProviderId

    if (-not $HistoryOnly) {
        $ccSwitch = Get-CabbageCcSwitchExe
        & $ccSwitch -a codex provider switch $switchId
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            throw "CC Switch failed with exit code $LASTEXITCODE."
        }
    }

    Sync-CodexHistoryProvider -ModelProvider $historyProvider -IncludeArchived:$IncludeArchived
}

function codex-openai {
    Z_switch default @args
}

function codex-api {
    Z_switch api @args
}

function codex-default {
    codex-openai @args
}

Set-Alias -Name cs-status -Value Show-CabbageSwitchStatus -Force
