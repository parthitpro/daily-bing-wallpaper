@echo off
setlocal
cd /d "%~dp0"
title Installing Daily Bing Wallpaper...
echo ========================================================
echo   Installing Daily Bing Wallpaper (Zero-Bloat Automation)
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Install.ps1"
echo.
echo ========================================================
echo   Done! Your desktop wallpaper is updated.
echo   Press any key to close this window.
echo ========================================================
pause >nul
