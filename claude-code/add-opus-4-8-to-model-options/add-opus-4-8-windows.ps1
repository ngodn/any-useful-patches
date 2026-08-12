# Adds an "Opus 4.8" entry to the Claude Code model picker (terminal CLI and
# the VS Code extension) by setting the ANTHROPIC_CUSTOM_MODEL_OPTION env vars
# in the user-level settings file (%USERPROFILE%\.claude\settings.json).
#
# Safe to re-run: if the option is already configured, the script exits
# without touching anything. Otherwise a timestamped backup is created first.
#
# Run with:  powershell -ExecutionPolicy Bypass -File .\add-opus-4-8-windows.ps1
# Works on Windows PowerShell 5.1 and PowerShell 7+.

$ErrorActionPreference = 'Stop'

$modelId   = 'claude-opus-4-8'
$modelName = 'Opus 4.8'
# Middle dot built from a char code so the file stays ASCII-safe
$middleDot = [char]0x00B7

$configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$settings  = Join-Path $configDir 'settings.json'

New-Item -ItemType Directory -Force -Path $configDir | Out-Null
if (-not (Test-Path $settings)) {
    [System.IO.File]::WriteAllText($settings, "{}`n")
}

$json = Get-Content $settings -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $json) { $json = [pscustomobject]@{} }

$hasEnv = ($json.PSObject.Properties.Name -contains 'env') -and ($null -ne $json.env)
if ($hasEnv -and $json.env.ANTHROPIC_CUSTOM_MODEL_OPTION -eq $modelId) {
    Write-Host "Already applied: $modelId is set in $settings, nothing to do."
    exit 0
}

$backup = "$settings.bak-$(Get-Date -Format yyyyMMdd-HHmmss)-$PID"
Copy-Item $settings $backup

if (-not $hasEnv) {
    $json | Add-Member -NotePropertyName 'env' -NotePropertyValue ([pscustomobject]@{}) -Force
}

$vars = [ordered]@{
    'ANTHROPIC_CUSTOM_MODEL_OPTION'             = $modelId
    'ANTHROPIC_CUSTOM_MODEL_OPTION_NAME'        = $modelName
    'ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION' = "$modelName $middleDot Previous Opus version"
}
foreach ($key in $vars.Keys) {
    $json.env | Add-Member -NotePropertyName $key -NotePropertyValue $vars[$key] -Force
}

try {
    $out = $json | ConvertTo-Json -Depth 100
    # Round-trip check before committing
    $out | ConvertFrom-Json | Out-Null
    [System.IO.File]::WriteAllText($settings, $out + "`n", (New-Object System.Text.UTF8Encoding($false)))
}
catch {
    Copy-Item $backup $settings -Force
    Write-Error "Failed to update $settings (restored from backup): $_"
    exit 1
}

Write-Host "Added `"$modelName`" ($modelId) to the Claude Code model picker."
Write-Host "Settings: $settings"
Write-Host "Backup:   $backup"
Write-Host "Start a new session (or reload the VS Code window) and check /model."
