#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads and applies the daily Bing 4K UHD wallpaper on Windows.
.DESCRIPTION
    Queries the official Bing public API for today's featured image, downloads
    the high-resolution 4K/UHD asset into Pictures\BingWallpapers, saves image
    metadata (title, copyright), applies the wallpaper via Win32 API, and auto-prunes
    wallpapers older than 30 days. Runs in ~1 second with zero background residency.
#>

[CmdletBinding()]
param(
    [string]$Market = "auto",
    [int]$RetentionDays = 30
)

# Use TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. Establish Directories
$PicturesDir = [Environment]::GetFolderPath('MyPictures')
$SaveDir = Join-Path -Path $PicturesDir -ChildPath 'BingWallpapers'
if (-not (Test-Path -Path $SaveDir)) {
    New-Item -ItemType Directory -Path $SaveDir -Force | Out-Null
}

# 2. Query Bing Public Image Archive API
$ApiUrl = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=$Market"
$WebClient = New-Object System.Net.WebClient
$WebClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) BingDailyWallpaper/1.0")

try {
    $RawJson = $WebClient.DownloadString($ApiUrl)
    $Data = $RawJson | ConvertFrom-Json
    $ImageInfo = $Data.images[0]
} catch {
    Write-Warning "Could not reach Bing API: $_"
    exit 1
}

if (-not $ImageInfo) {
    Write-Warning "No image information returned from Bing."
    exit 1
}

$StartDate = $ImageInfo.startdate
$Title     = $ImageInfo.title
$Copyright = $ImageInfo.copyright

# 3. Determine Image URLs (Prioritize 4K UHD, fallback to 1080p standard URL)
$UhdUrl = "https://www.bing.com" + $ImageInfo.urlbase + "_UHD.jpg"
$StandardUrl = "https://www.bing.com" + $ImageInfo.url

$TargetFile = Join-Path -Path $SaveDir -ChildPath "Bing_$StartDate.jpg"
$MetaFile   = Join-Path -Path $SaveDir -ChildPath "Bing_$StartDate.json"

# 4. Check if today's image is already downloaded
$NeedDownload = -not (Test-Path -Path $TargetFile) -or ((Get-Item -Path $TargetFile).Length -eq 0)

if ($NeedDownload) {
    Write-Host "Downloading today's Bing wallpaper: $Title" -ForegroundColor Cyan
    $Downloaded = $false

    # Attempt 4K UHD download first
    try {
        $WebClient.DownloadFile($UhdUrl, $TargetFile)
        if ((Get-Item -Path $TargetFile).Length -gt 100000) {
            $Downloaded = $true
            Write-Host "Downloaded 4K UHD image successfully." -ForegroundColor Green
        }
    } catch {
        # Fallback to standard 1080p
        $Downloaded = $false
    }

    if (-not $Downloaded) {
        try {
            $WebClient.DownloadFile($StandardUrl, $TargetFile)
            Write-Host "Downloaded 1080p image successfully." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to download wallpaper: $_"
            exit 1
        }
    }

    # Save metadata info for attribution and story context
    $MetaContent = [PSCustomObject]@{
        Date      = $StartDate
        Title     = $Title
        Copyright = $Copyright
        UhdUrl    = $UhdUrl
        StdUrl    = $StandardUrl
    } | ConvertTo-Json -Depth 2
    Set-Content -Path $MetaFile -Value $MetaContent -Encoding UTF8
} else {
    Write-Host "Today's wallpaper ($StartDate) already exists in cache." -ForegroundColor Yellow
}

# 5. Switch Windows 11 Background Mode to Picture & Apply Wallpaper
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -Name BackgroundType -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value 10 -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper  -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallPaper -Value $TargetFile -ErrorAction SilentlyContinue

$Definition = @"
using System;
using System.Runtime.InteropServices;

public class WinWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
"@

if (-not ([System.Management.Automation.PSTypeName]'WinWallpaper').Type) {
    Add-Type -TypeDefinition $Definition
}

# SPI_SETDESKWALLPAPER = 20 (0x0014)
# SPIF_UPDATEINIFILE = 0x01, SPIF_SENDCHANGE = 0x02 -> 3
$SpiResult = [WinWallpaper]::SystemParametersInfo(20, 0, $TargetFile, 3)

# Broadcast WM_SETTINGCHANGE (0x001A) to HWND_BROADCAST (0xFFFF) so Windows Explorer refreshes the wallpaper instantly
$NullResult = [UIntPtr]::Zero
[WinWallpaper]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$NullResult) | Out-Null

Write-Host "Desktop wallpaper updated to: $Title ($StartDate) [Result: $SpiResult]" -ForegroundColor Green

# 6. Auto-Cleanup old wallpapers (Older than RetentionDays)
try {
    $OldFiles = Get-ChildItem -Path $SaveDir -Filter "Bing_*" | Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays)
    }
    foreach ($File in $OldFiles) {
        Remove-Item -Path $File.FullName -Force -ErrorAction SilentlyContinue
    }
} catch {
    # Non-critical, ignore
}
