#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the daily Bing Wallpaper scheduled task on Windows.
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkerScript = Join-Path -Path $ScriptDir -ChildPath "Update-BingWallpaper.ps1"
$TaskName = "DailyBingWallpaper"

if (-not (Test-Path -LiteralPath $WorkerScript)) {
    Write-Error "Could not find Update-BingWallpaper.ps1 at $WorkerScript"
    exit 1
}

Write-Host "Registering scheduled task '$TaskName'..." -ForegroundColor Cyan

# Define Action: run powershell hidden with execution policy bypass
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WorkerScript`""

# Define Triggers:
# 1. At user logon (using current user account name)
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$TriggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser

# 2. Daily at 9:00 AM
$TriggerDaily = New-ScheduledTaskTrigger -Daily -At "09:00 AM"

# Define Settings: run on battery, start when available if missed, wake to run
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun -MultipleInstances IgnoreNew

# Unregister previous instance if existing
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

# Register new Task
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger @($TriggerLogon, $TriggerDaily) -Settings $Settings -Description "Fetches and applies the daily Bing 4K UHD wallpaper silently." | Out-Null

Write-Host "Task '$TaskName' registered successfully!" -ForegroundColor Green

# Run once now to verify
Write-Host "Verifying wallpaper update now..." -ForegroundColor Cyan
& $WorkerScript
