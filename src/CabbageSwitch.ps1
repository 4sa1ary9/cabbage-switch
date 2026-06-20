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
import re
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    cur = conn.cursor()
    rows = cur.execute("""
        SELECT id, name, category, provider_type, is_current, sort_index, settings_config
        FROM providers
        WHERE app_type = 'codex'
        ORDER BY sort_index IS NULL, sort_index, name
    """).fetchall()

    def history_bucket(provider_id, model_provider):
        mp = (model_provider or "").lower()
        if provider_id == "default" or mp in ("default", "openai", "oai", "official"):
            return "openai"
        if model_provider:
            return model_provider
        return "custom"

    result = []
    for row in rows:
        provider_id = row[0]
        try:
            settings = json.loads(row[6] or "{}")
        except Exception:
            settings = {}
        config_text = settings.get("config") or ""
        match = re.search(r'^\s*model_provider\s*=\s*"([^"]+)"', config_text, re.M)
        model_provider = match.group(1) if match else None
        result.append({
            "id": provider_id,
            "name": row[1],
            "category": row[2],
            "provider_type": row[3],
            "is_current": bool(row[4]),
            "sort_index": row[5],
            "model_provider": model_provider,
            "history_provider": history_bucket(provider_id, model_provider),
        })
    print(json.dumps(result, ensure_ascii=False))
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
                ([string] $_.name).Equals($ProviderId, [System.StringComparison]::OrdinalIgnoreCase) -or
                ([string] $_.model_provider).Equals($ProviderId, [System.StringComparison]::OrdinalIgnoreCase)
            }
    ) | Select-Object -First 1
    if ($matched) {
        return [string] $matched.id
    }

    return $ProviderId
}

function Test-CabbageCodexProviderKnown {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ProviderId
    )

    $key = $ProviderId.ToLowerInvariant()
    if ($key -in @('default', 'openai', 'oai', 'official')) {
        return $true
    }

    $providers = @(Get-CabbageCodexProviders)
    if ($key -in @('api', 'custom', 'proxy')) {
        return (@($providers | Where-Object { $_.id -ne 'default' })).Count -gt 0
    }

    foreach ($provider in $providers) {
        if ($provider.id -eq $ProviderId) { return $true }
        if (([string] $provider.name).Equals($ProviderId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if (([string] $provider.model_provider).Equals($ProviderId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }

    return $false
}

function Get-CabbageModelProviderFromConfigText {
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [string] $ConfigText
    )

    if ([string]::IsNullOrWhiteSpace($ConfigText)) {
        return $null
    }

    foreach ($line in ($ConfigText -split "`r?`n")) {
        if ($line -match '^\s*model_provider\s*=\s*"([^"]+)"') {
            return $Matches[1]
        }
    }

    return $null
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

    try {
        $configProvider = Get-CabbageModelProviderFromConfigText (Get-CabbageCodexProviderConfigText $switchId)
        if (-not [string]::IsNullOrWhiteSpace($configProvider)) {
            return $configProvider
        }
    }
    catch {
    }

    $currentProvider = Get-CabbageCodexConfigProvider
    if ((Resolve-CabbageConfigProviderHistoryBucket $currentProvider) -eq 'custom') {
        return $currentProvider
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
        [string] $ModelProvider
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    $text = [System.IO.File]::ReadAllText($Path, $encoding)
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    $newline = [System.Text.RegularExpressions.Regex]::Match($text, "`r?`n")
    if ($newline.Success) {
        $firstLine = $text.Substring(0, $newline.Index)
        $lineEnding = $newline.Value
        $rest = $text.Substring($newline.Index + $newline.Length)
    }
    else {
        $firstLine = $text
        $lineEnding = ''
        $rest = ''
    }

    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        return $false
    }

    $meta = $firstLine | ConvertFrom-Json -ErrorAction Stop
    if ($meta.type -ne 'session_meta' -or -not $meta.payload) {
        return $false
    }

    if ($meta.payload.PSObject.Properties.Match('model_provider').Count -eq 0) {
        $meta.payload | Add-Member -NotePropertyName model_provider -NotePropertyValue $ModelProvider
    }
    else {
        $meta.payload.model_provider = $ModelProvider
    }

    $updatedFirstLine = $meta | ConvertTo-Json -Depth 100 -Compress
    [System.IO.File]::WriteAllText($Path, $updatedFirstLine + $lineEnding + $rest, $encoding)
    return $true
}

function Sync-CabbageCodexJsonlHistoryProvider {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
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
                elseif ($WhatIfPreference) {
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
should_write = sys.argv[4] == "1"

conn = sqlite3.connect(db_path)
try:
    cur = conn.cursor()
    if include_archived:
        total = cur.execute("SELECT COUNT(*) FROM threads").fetchone()[0]
        changed = cur.execute(
            """
            SELECT COUNT(*) FROM threads
            WHERE model_provider IS NULL OR model_provider <> ?
            """,
            (model_provider,),
        ).fetchone()[0]
        if should_write:
            cur.execute(
                """
                UPDATE threads
                SET model_provider = ?
                WHERE model_provider IS NULL OR model_provider <> ?
                """,
                (model_provider, model_provider),
            )
    else:
        total = cur.execute("SELECT COUNT(*) FROM threads WHERE archived = 0").fetchone()[0]
        changed = cur.execute(
            """
            SELECT COUNT(*) FROM threads
            WHERE archived = 0
              AND (model_provider IS NULL OR model_provider <> ?)
            """,
            (model_provider,),
        ).fetchone()[0]
        if should_write:
            cur.execute(
                """
                UPDATE threads
                SET model_provider = ?
                WHERE archived = 0
                  AND (model_provider IS NULL OR model_provider <> ?)
                """,
                (model_provider, model_provider),
            )

    if should_write:
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
        $result = Invoke-CabbagePythonJson -Script $script -Arguments @($databasePath, $ModelProvider, $(if ($IncludeArchived) { '1' } else { '0' }), '0')
        if ([int] $result.changed -gt 0 -and $PSCmdlet.ShouldProcess($databasePath, "set threads.model_provider to $ModelProvider")) {
            $backupPath = Backup-CabbageCodexStateDatabase $databasePath
            $result = Invoke-CabbagePythonJson -Script $script -Arguments @($databasePath, $ModelProvider, $(if ($IncludeArchived) { '1' } else { '0' }), '1')
        }

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

function Repair-CabbageHermesConfig {
    $configPath = Join-Path $HOME '.hermes\config.yaml'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    [System.IO.File]::ReadAllLines($configPath) | ForEach-Object { $lines.Add($_) }

    $mcpIndexes = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^mcp_servers\s*:') {
            $mcpIndexes += $i
        }
    }

    if ($mcpIndexes.Count -le 1) {
        return $null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$configPath.cabbage-switch-$timestamp.bak"
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force

    for ($index = $mcpIndexes.Count - 2; $index -ge 0; $index--) {
        $removeStart = $mcpIndexes[$index]
        $removeEnd = $lines.Count
        for ($i = $removeStart + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^[A-Za-z0-9_-]+\s*:') {
                $removeEnd = $i
                break
            }
        }

        while ($removeEnd -gt $removeStart -and [string]::IsNullOrWhiteSpace($lines[$removeEnd - 1])) {
            $removeEnd--
        }

        $lines.RemoveRange($removeStart, $removeEnd - $removeStart)
    }

    [System.IO.File]::WriteAllLines($configPath, $lines, [System.Text.UTF8Encoding]::new($false))
    return $backupPath
}

function Get-CabbageCodexProviderConfigText {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ProviderId
    )

    $dbPath = Join-Path (Get-CabbageCcSwitchHome) 'cc-switch.db'
    if (-not (Test-Path -LiteralPath $dbPath)) {
        throw 'CC Switch database was not found. Configure CC Switch first.'
    }

    $script = @'
import json
import sqlite3
import sys

db_path = sys.argv[1]
provider_id = sys.argv[2]

conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    row = conn.execute(
        "SELECT settings_config FROM providers WHERE app_type = 'codex' AND id = ?",
        (provider_id,),
    ).fetchone()
    if row is None:
        print(json.dumps({"found": False, "config": None}))
    else:
        settings = json.loads(row[0] or "{}")
        print(json.dumps({"found": True, "config": settings.get("config")}, ensure_ascii=False))
finally:
    conn.close()
'@

    $result = Invoke-CabbagePythonJson -Script $script -Arguments @($dbPath, $ProviderId)
    if (-not $result.found) {
        throw "Codex provider '$ProviderId' was not found in CC Switch."
    }

    if ([string]::IsNullOrWhiteSpace([string] $result.config)) {
        throw "Codex provider '$ProviderId' does not have a config payload in CC Switch."
    }

    return [string] $result.config
}

function Set-CabbageCodexConfigFromProvider {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ProviderId
    )

    $configText = Get-CabbageCodexProviderConfigText $ProviderId
    $codexHome = Get-CabbageCodexHome
    New-Item -ItemType Directory -Force -Path $codexHome | Out-Null

    $configPath = Join-Path $codexHome 'config.toml'
    if (Test-Path -LiteralPath $configPath) {
        $backupDir = Join-Path $codexHome 'backups'
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = Join-Path $backupDir "config.toml.cabbage-switch-$timestamp.bak"
        Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    }

    [System.IO.File]::WriteAllText($configPath, $configText, [System.Text.UTF8Encoding]::new($false))
}

function Set-CabbageCcSwitchCurrentCodexProvider {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ProviderId
    )

    $dbPath = Join-Path (Get-CabbageCcSwitchHome) 'cc-switch.db'
    if (Test-Path -LiteralPath $dbPath) {
        $script = @'
import sqlite3
import sys

db_path = sys.argv[1]
provider_id = sys.argv[2]

conn = sqlite3.connect(db_path)
try:
    cur = conn.cursor()
    exists = cur.execute(
        "SELECT 1 FROM providers WHERE app_type = 'codex' AND id = ?",
        (provider_id,),
    ).fetchone() is not None
    if not exists:
        raise SystemExit(f"Provider not found: {provider_id}")
    cur.execute("UPDATE providers SET is_current = 0 WHERE app_type = 'codex'")
    cur.execute(
        "UPDATE providers SET is_current = 1 WHERE app_type = 'codex' AND id = ?",
        (provider_id,),
    )
    conn.commit()
    print("{}")
finally:
    conn.close()
'@

        Invoke-CabbagePythonJson -Script $script -Arguments @($dbPath, $ProviderId) | Out-Null
    }

    $settingsPath = Join-Path (Get-CabbageCcSwitchHome) 'settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.cabbage-switch-$timestamp.bak" -Force
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $settings.currentProviderCodex = $ProviderId
        $json = $settings | ConvertTo-Json -Depth 100
        [System.IO.File]::WriteAllText($settingsPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    }
}

function Get-CabbageCodexConfigProvider {
    $configPath = Join-Path (Get-CabbageCodexHome) 'config.toml'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    foreach ($line in Get-Content -LiteralPath $configPath) {
        if ($line -match '^\s*model_provider\s*=\s*"([^"]+)"') {
            return $Matches[1]
        }
    }

    return 'openai'
}

function Resolve-CabbageConfigProviderHistoryBucket {
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [string] $ConfigProvider
    )

    if ([string]::IsNullOrWhiteSpace($ConfigProvider)) {
        return $null
    }

    $key = $ConfigProvider.ToLowerInvariant()
    if ($key -in @('default', 'openai', 'oai', 'official')) {
        return 'openai'
    }

    return 'custom'
}

function Test-CabbageCodexConfigProvider {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ExpectedProvider
    )

    $actualProvider = Get-CabbageCodexConfigProvider
    if ($ExpectedProvider -in @('openai', 'custom')) {
        return (Resolve-CabbageConfigProviderHistoryBucket $actualProvider) -eq $ExpectedProvider
    }

    return $actualProvider -eq $ExpectedProvider
}

function Assert-CabbageCodexConfigProvider {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ExpectedProvider
    )

    $actualProvider = Get-CabbageCodexConfigProvider
    if (-not (Test-CabbageCodexConfigProvider $ExpectedProvider)) {
        $displayActual = if ($actualProvider) { $actualProvider } else { '<missing>' }
        throw "Codex provider switch did not complete. Expected ~/.codex/config.toml model_provider '$ExpectedProvider', found '$displayActual'. History was not synced. Fix the CC Switch error, then rerun this command."
    }
}

function Ensure-CabbageCodexProviderSwitch {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ProviderId,

        [Parameter(Mandatory = $true)]
        [string] $HistoryProvider
    )

    if (-not (Test-CabbageCodexConfigProvider $HistoryProvider)) {
        Set-CabbageCodexConfigFromProvider $ProviderId
    }

    Set-CabbageCcSwitchCurrentCodexProvider $ProviderId
}

function Show-CabbageSwitchStatus {
    $configProvider = Get-CabbageCodexConfigProvider
    $configHistoryBucket = Resolve-CabbageConfigProviderHistoryBucket $configProvider

    [pscustomobject]@{
        CodexHome           = Get-CabbageCodexHome
        CcSwitchHome        = Get-CabbageCcSwitchHome
        CcSwitchExe         = $(try { Get-CabbageCcSwitchExe } catch { $null })
        CodexConfig         = $configProvider
        CodexHistoryBucket  = $configHistoryBucket
        StateDatabase       = Get-CabbageCodexStateDatabase
        ApiProviderId       = $(try { Resolve-CabbageCodexApiProviderId } catch { $null })
        ApiHistoryProvider  = $(try { Resolve-CabbageHistoryProvider api } catch { $null })
    }

    Get-CabbageCodexProviders |
        Select-Object id, name, category, provider_type, is_current |
        Format-Table -AutoSize

    Get-CodexStateProviderSummary | Format-Table -AutoSize
    Get-CodexHistoryProviderSummary | Format-Table -AutoSize
}

function Z_switch {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $ProviderId,

        [switch] $SwitchProvider,
        [switch] $HistoryOnly,
        [switch] $IncludeArchived
    )

    $switchId = Resolve-CabbageCodexProviderSwitchId $ProviderId
    $historyProvider = Resolve-CabbageHistoryProvider $ProviderId

    if ($HistoryOnly) {
        Write-Verbose '-HistoryOnly is now the default behavior; ignoring the switch.'
    }

    if ($SwitchProvider) {
        if ($PSCmdlet.ShouldProcess("Codex provider '$switchId'", 'switch CC Switch provider and Codex config')) {
            $ccSwitch = Get-CabbageCcSwitchExe
            Repair-CabbageHermesConfig | Out-Null
            $global:LASTEXITCODE = $null
            & $ccSwitch -a codex provider switch $switchId
            if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
                throw "CC Switch failed with exit code $LASTEXITCODE. History was not synced."
            }

            Ensure-CabbageCodexProviderSwitch -ProviderId $switchId -HistoryProvider $historyProvider
            Assert-CabbageCodexConfigProvider $historyProvider
            Repair-CabbageHermesConfig | Out-Null
        }
    }

    Sync-CodexHistoryProvider -ModelProvider $historyProvider -IncludeArchived:$IncludeArchived
}

function Show-CabbageSwitchGuidance {
    $providers = @(Get-CabbageCodexProviders)

    if ($providers.Count -eq 0) {
        Write-Host 'No Codex providers were found in CC Switch.' -ForegroundColor Yellow
        Write-Host 'Open CC Switch and add at least one Codex provider, then rerun cabbage-switch.'
        return
    }

    Write-Host 'Detected Codex providers:' -ForegroundColor Cyan
    foreach ($p in $providers) {
        $label = [string] $p.name
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = $p.id
        }
        $marker = if ($p.is_current) { '   [current]' } else { '' }
        Write-Host ("  {0,-18} {1,-22} -> {2}{3}" -f $p.id, $label, $p.history_provider, $marker)
    }

    Write-Host ''
    Write-Host 'Move active history to a provider bucket (history only, the default):' -ForegroundColor Cyan
    foreach ($p in $providers) {
        Write-Host ("  cabbage-switch {0}" -f $p.id)
    }
    Write-Host ''
    Write-Host 'Add -SwitchProvider to also switch the active provider through CC Switch.'
    Write-Host 'Add -IncludeArchived to also move archived threads.'
    Write-Host 'Add -WhatIf to preview without changing anything.'
    Write-Host ''
    Write-Host 'Run cs-status for full path and history-count details.'
}

function cabbage-switch {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Position = 0)]
        [string] $Provider,

        [switch] $SwitchProvider,
        [switch] $HistoryOnly,
        [switch] $IncludeArchived
    )

    if ([string]::IsNullOrWhiteSpace($Provider)) {
        Show-CabbageSwitchGuidance
        return
    }

    if (-not (Test-CabbageCodexProviderKnown $Provider)) {
        Write-Warning ("Provider '{0}' is not a detected Codex provider in CC Switch." -f $Provider)
        Write-Warning 'History was not changed.'
        Write-Host ''
        Show-CabbageSwitchGuidance
        return
    }

    Z_switch $Provider -SwitchProvider:$SwitchProvider -HistoryOnly:$HistoryOnly -IncludeArchived:$IncludeArchived -WhatIf:$WhatIfPreference
}

Set-Alias -Name c-switch -Value cabbage-switch -Force
Set-Alias -Name cs-status -Value Show-CabbageSwitchStatus -Force
