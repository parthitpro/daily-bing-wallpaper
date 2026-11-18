@echo off
setlocal
cd /d "%~dp0"
title Uninstalling Daily Bing Wallpaper...
echo ========================================================
echo   Uninstalling Daily Bing Wallpaper
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Uninstall.ps1"
if errorlevel 1 (
    echo.
    echo ERROR: Uninstall step encountered an issue.
    pause >nul
    exit /b 1
)
echo.
echo ========================================================
echo   Removed cleanly. Press any key to close this window.
echo ========================================================
pause >nul
exit /b 0
