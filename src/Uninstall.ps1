#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls the daily Bing Wallpaper scheduled task.
#>

$TaskName = "DailyBingWallpaper"

Write-Host "Removing scheduled task '$TaskName'..." -ForegroundColor Yellow
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
Write-Host "Task '$TaskName' removed successfully." -ForegroundColor Green
Write-Host "Note: Downloaded wallpapers in Pictures\BingWallpapers were preserved." -ForegroundColor Cyan
