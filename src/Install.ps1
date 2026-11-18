#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the daily Bing Wallpaper scheduled task on Windows.
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkerScript = Join-Path -Path $ScriptDir -ChildPath "Update-BingWallpaper.ps1"
$TaskName = "DailyBingWallpaper"

if (-not (Test-Path -Path $WorkerScript)) {
    Write-Error "Could not find Update-BingWallpaper.ps1 at $WorkerScript"
    exit 1
}

Write-Host "Registering scheduled task '$TaskName'..." -ForegroundColor Cyan

# Define Action: run powershell hidden
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WorkerScript`""

# Define Triggers:
# 1. At user logon
$TriggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# 2. Daily at 9:00 AM
$TriggerDaily = New-ScheduledTaskTrigger -Daily -At "09:00 AM"

# Define Settings: Wake to run if asleep, run as soon as possible if missed
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

# Unregister previous instance if existing
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

# Register new Task
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger @($TriggerLogon, $TriggerDaily) -Settings $Settings -Description "Fetches and applies the daily Bing 4K UHD wallpaper silently." | Out-Null

Write-Host "Task '$TaskName' registered successfully!" -ForegroundColor Green

# Run once now to immediately set today's wallpaper
Write-Host "Fetching and setting today's wallpaper now..." -ForegroundColor Cyan
& $WorkerScript
