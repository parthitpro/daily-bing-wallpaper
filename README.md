# Daily Bing Wallpaper Automation (Windows 10 & 11)

A lightweight, open-source Windows automation tool that updates your desktop wallpaper with Bing's daily featured picture in high quality (4K UHD / 1080p).

---

## Why This Instead of the Official App or Other Software?

| Feature | Official Bing App / Tray Utilities | **This Repository** |
| :--- | :--- | :--- |
| **Idle Memory (RAM)** | 60 MB – 150 MB continuous memory usage | **No persistent background process** (terminates after running) |
| **Background CPU** | Periodic checks & continuous threads | **0.0% idle CPU** |
| **Bloatware / Promos** | Often promotes Edge/Bing searches | **None** (Clean script, zero unwanted software) |
| **Execution Duration** | Stays running 24/7 | **A few seconds** per execution, then unloads |
| **Windows 11 Spotlight** | Often overridden by Windows Spotlight | **Automatically sets Picture mode (`BackgroundType = 0`)** |
| **Dependencies** | Requires heavy runtimes | **Zero dependencies** (Built into standard Windows) |

---

## Key Features

1. **True 4K UHD Quality**: Prioritizes Microsoft's official `_UHD.jpg` (3840x2160) asset with graceful fallback to standard 1080p.
2. **Windows 11 Compatibility**: Automatically handles the Windows 11 Spotlight override to ensure wallpapers apply reliably across updates.
3. **Smart 18-Hour Caching**: Automatically uses the cached image if updated within the last 18 hours, preventing unnecessary network queries.
4. **Auto-Cleanup (Pruning)**: Automatically cleans up wallpapers older than 30 days so your disk space remains pristine.
5. **Caption & Metadata Preservation**: Saves a companion `.json` file containing title, photographer/agency copyright, and description.
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
├── README.md                 # Documentation and troubleshooting
├── LICENSE                   # Open-source license & personal use attribution
└── src/
    ├── Update-BingWallpaper.ps1  # Core engine: API fetch, 4K download, Windows 11 unlock, apply wallpaper
    ├── Install.ps1               # Registers Task Scheduler job with logon + 9:00 AM daily triggers
    └── Uninstall.ps1             # Safely unregisters Task Scheduler job
```

---

## Schedule & Behavior Details

- **Triggers**:
  - **Every day at 09:00 AM**
  - **At user logon / PC boot** (checks if the cached image is older than 18 hours and refreshes if needed).
- **Silent Execution**: Configured with `-WindowStyle Hidden` so no command prompt flashes on your screen.
- **Storage Location**: Images are saved in your personal pictures directory:
  ```text
  %USERPROFILE%\Pictures\BingWallpapers\
  ```

---

## Security & Architecture Note

- Scripts run via `-ExecutionPolicy Bypass` under the user account. Keep this folder in a personal directory to ensure non-administrative users cannot modify the source script.

---

## License & Attribution

Distributed under the [MIT License](LICENSE).
Wallpapers provided by Bing are copyrighted by their respective photographers and Microsoft, and are intended for personal desktop viewing.
