# Sets up the Lumisound Discord Rich Presence daemon to run at login on Windows.
#
# Requires Python 3 (https://www.python.org/downloads/ — check "Add python.exe
# to PATH" during install).
#
# Usage (in PowerShell):
#   .\install-windows.ps1 -Token "<rpc_token>" [-BridgeUrl "https://..."]
#
# Get <rpc_token> from Lumisound -> Account -> Discord Rich Presence ->
# Generate Rich Presence Token.

param(
    [Parameter(Mandatory = $true)]
    [string]$Token,

    [string]$BridgeUrl = ""
)

$ConfigDir = Join-Path $env:APPDATA "lumisound-discord-rpc"
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

$Config = @{
    access_token         = $Token
    poll_interval_seconds = 5
}
if ($BridgeUrl) {
    $Config["bridge_url"] = $BridgeUrl
}
$ConfigPath = Join-Path $ConfigDir "config.json"
$Config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
Write-Host "Wrote $ConfigPath"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptPath = Join-Path $ScriptDir "lumisound_discord_rpc.py"

$Python = (Get-Command python -ErrorAction SilentlyContinue).Path
if (-not $Python) {
    $Python = (Get-Command python3 -ErrorAction SilentlyContinue).Path
}
if (-not $Python) {
    Write-Error "Python 3 not found. Install it from https://www.python.org/downloads/ and re-run this script."
    exit 1
}

# Register a logon task that restarts the daemon if it ever exits.
$Action = New-ScheduledTaskAction -Execute $Python -Argument "`"$ScriptPath`""
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -Hidden -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)
Register-ScheduledTask -TaskName "LumisoundDiscordRPC" -Action $Action -Trigger $Trigger -Settings $Settings -Force | Out-Null

Write-Host "Registered scheduled task 'LumisoundDiscordRPC' (runs at login)."
Write-Host "Starting it now..."
Start-ScheduledTask -TaskName "LumisoundDiscordRPC"

Write-Host ""
Write-Host "Check status with:"
Write-Host "  Get-ScheduledTask -TaskName LumisoundDiscordRPC"
Write-Host "Stop it with:"
Write-Host "  Stop-ScheduledTask -TaskName LumisoundDiscordRPC; Unregister-ScheduledTask -TaskName LumisoundDiscordRPC -Confirm:`$false"
