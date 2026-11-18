@echo off
setlocal
cd /d "%~dp0"
title Fetching Today's Bing Wallpaper...
echo ========================================================
echo   Updating to today's Bing 4K Wallpaper...
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Update-BingWallpaper.ps1"
if errorlevel 1 (
    echo.
    echo ERROR: Wallpaper update failed. See details above.
    pause >nul
    exit /b 1
)
echo.
echo ========================================================
echo   Finished! Press any key to close this window.
echo ========================================================
pause >nul
exit /b 0
