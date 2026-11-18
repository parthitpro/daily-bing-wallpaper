# Daily Bing Wallpaper Automation (Windows 10 & 11)

A lightweight, zero-bloat, open-source Windows automation tool that updates your desktop wallpaper every day with Bing's featured picture in high quality (4K UHD / 1080p).

---

## Why This Instead of the Official App or Other Software?

| Feature | Official Bing App / Tray Utilities | **This Repository** |
| :--- | :--- | :--- |
| **Idle Memory (RAM)** | 60 MB – 150 MB (runs 24/7) | **0 MB** (Terminates immediately after run) |
| **Background CPU** | Periodic checks & background threads | **0.0%** |
| **Bloatware / Promos** | Often promotes Edge/Bing searches | **None** (Pure script, 0 apps installed) |
| **Execution Time** | Continuous | **1–2 seconds total** once per day |
| **Windows 11 Spotlight** | Often conflicts with Spotlight settings | **Auto-unlocks Windows 11 Spotlight mode** |
| **Dependencies** | Requires installer / runtimes | **Zero dependencies** (Built into Windows) |

---

## Key Features

1. **True 4K UHD Quality**: Prioritizes Microsoft's official `_UHD.jpg` (3840x2160) asset with graceful fallback to standard 1080p.
2. **Windows 11 Compatibility**: Automatically handles the Windows 11 Spotlight override (`BackgroundType` registry unlock) to ensure wallpapers apply reliably on all builds.
3. **Smart Caching & Rate-Limit Safe**: Checks if today's wallpaper is already downloaded before querying, strictly preventing redundant network requests.
4. **Auto-Cleanup (Pruning)**: Automatically cleans up wallpapers older than 30 days so your disk space remains pristine.
5. **Caption & Metadata Preservation**: Saves a companion `.json` file for every image containing the official title, photographer/agency copyright, and description for proper attribution.
6. **Zero External Dependencies**: Works out-of-the-box on clean Windows installations using built-in PowerShell 5.1+ and Task Scheduler.

---

## Quick Start (1-Click Setup)

1. **Download or Clone** this repository to your computer.
2. **Double-click `install.bat`**.
3. **Done!** Today's 4K Bing wallpaper is applied immediately, and a silent background task is registered to update it every morning.

---

## File Overview

```text
daily-bing-wallpaper/
├── install.bat               # 1-click installer: sets up daily scheduled task & applies wallpaper
├── uninstall.bat             # 1-click uninstaller: cleanly removes the scheduled task
├── run-now.bat               # 1-click manual refresh: updates wallpaper right now on demand
├── README.md                 # Full documentation and troubleshooting
├── LICENSE                   # MIT Open-Source License
└── src/
    ├── Update-BingWallpaper.ps1  # Core engine: API fetch, 4K download, Windows 11 unlock, apply wallpaper
    ├── Install.ps1               # Registers Task Scheduler job with logon + 9:00 AM daily triggers
    └── Uninstall.ps1             # Safely unregisters Task Scheduler job
```

---

## Schedule & Behavior Details

- **Triggers**:
  - **Every day at 09:00 AM**
  - **At user logon / PC boot** (if your PC was turned off at 9:00 AM, it catches up as soon as you boot up).
- **Silent Execution**: Configured with `-WindowStyle Hidden` so no command prompt or black window ever flashes on your screen.
- **Storage Location**: Images are saved in your personal pictures directory:
  ```text
  %USERPROFILE%\Pictures\BingWallpapers\
  ```

---

## Manual Execution / Commands

If you prefer running via PowerShell directly:

```powershell
# Run the wallpaper update immediately:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\src\Update-BingWallpaper.ps1"

# Install the daily schedule:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\src\Install.ps1"

# Uninstall:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\src\Uninstall.ps1"
```

---

## Technical Notes: Windows 11 Spotlight Handling

On Windows 11, if the system was previously set to "Windows Spotlight", Windows locks the desktop background to cached spotlight images, ignoring standard API wallpaper updates. 

This repository's script automatically resolves this by:
1. Setting `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers` -> `BackgroundType = 0` (Picture mode).
2. Updating the registry wallpaper properties (`WallpaperStyle = 10` for Fill).
3. Invoking the Win32 `SystemParametersInfo(SPI_SETDESKWALLPAPER)` API.
4. Broadcasting `WM_SETTINGCHANGE` to notify the Windows shell immediately.

---

## License & Attribution

Distributed under the [MIT License](LICENSE).
Wallpapers provided by Bing are copyrighted by their respective photographers and Microsoft, and are intended for personal desktop viewing.
