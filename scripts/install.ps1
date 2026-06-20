[CmdletBinding()]
param(
    [string] $InstallRoot = (Join-Path $HOME '.cabbage-switch'),
    [string] $ProfilePath = $PROFILE,
    [string] $RawBaseUrl = 'https://raw.githubusercontent.com/4sa1ary9/cabbage-switch/main',
    [switch] $AllHosts,
    [switch] $NoProfileUpdate
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if ($AllHosts -and $PROFILE.CurrentUserAllHosts) {
    $ProfilePath = $PROFILE.CurrentUserAllHosts
}

$moduleName = 'CabbageSwitch.ps1'
$moduleTarget = Join-Path $InstallRoot $moduleName
$localModule = Join-Path (Split-Path -Parent $PSScriptRoot) "src\$moduleName"

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

if (Test-Path -LiteralPath $localModule) {
    Copy-Item -LiteralPath $localModule -Destination $moduleTarget -Force
}
else {
    $moduleUrl = "$RawBaseUrl/src/$moduleName"
    Invoke-WebRequest -Uri $moduleUrl -OutFile $moduleTarget -UseBasicParsing
}

if (-not $NoProfileUpdate) {
    $profileDir = Split-Path -Parent $ProfilePath
    if ($profileDir) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    $begin = '# >>> cabbage-switch >>>'
    $end = '# <<< cabbage-switch <<<'
    $escapedModuleTarget = $moduleTarget.Replace("'", "''")
    $block = @(
        $begin
        ". '$escapedModuleTarget'"
        $end
    ) -join [Environment]::NewLine

    $profileText = ''
    if (Test-Path -LiteralPath $ProfilePath) {
        $profileText = Get-Content -LiteralPath $ProfilePath -Raw
    }

    $pattern = "(?ms)^# >>> cabbage-switch >>>.*?^# <<< cabbage-switch <<<\r?\n?"
    if ($profileText -match $pattern) {
        $profileText = [System.Text.RegularExpressions.Regex]::Replace($profileText, $pattern, $block + [Environment]::NewLine)
    }
    else {
        if ($profileText -and -not $profileText.EndsWith([Environment]::NewLine)) {
            $profileText += [Environment]::NewLine
        }
        $profileText += $block + [Environment]::NewLine
    }

    Set-Content -LiteralPath $ProfilePath -Value $profileText -Encoding UTF8
}

. $moduleTarget

Write-Host 'Cabbage Switch installed.' -ForegroundColor Green
Write-Host "Module:  $moduleTarget"
if (-not $NoProfileUpdate) {
    Write-Host "Profile: $ProfilePath"
}
Write-Host ''
Write-Host 'Available commands:'
Write-Host '  codex-api [-IncludeArchived]'
Write-Host '  codex-openai [-IncludeArchived]'
Write-Host '  codex-api -SwitchProvider [-IncludeArchived]'
Write-Host '  codex-openai -SwitchProvider [-IncludeArchived]'
Write-Host '  Show-CabbageSwitchStatus'
Write-Host ''
Write-Host 'Run this once in the current shell, or open a new PowerShell window:'
Write-Host ". '$moduleTarget'"
