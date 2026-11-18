#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads and applies the daily Bing 4K UHD wallpaper on Windows.
.DESCRIPTION
    Hardened daily Bing wallpaper automation:
    - Pre-check local cache to prevent redundant API queries.
    - URL pinning strictly to www.bing.com.
    - Atomic download (.tmp file) with JPEG magic byte validation.
    - Strict startdate regex validation.
    - Switches Windows 11 BackgroundType to Picture mode (0).
    - Verifies Win32 SystemParametersInfo return status.
    - Auto-prunes wallpapers older than retention period.
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
if (-not (Test-Path -LiteralPath $SaveDir)) {
    New-Item -ItemType Directory -Path $SaveDir -Force | Out-Null
}

# 2. Pre-API Check: If today's local wallpaper exists, check before contacting API
$TodayTag = (Get-Date).ToString("yyyyMMdd")
$TodayPattern = "Bing_$TodayTag.jpg"
$ExistingToday = Get-ChildItem -LiteralPath $SaveDir -Filter $TodayPattern -ErrorAction SilentlyContinue

function Apply-WallpaperFile {
    param([string]$FilePath, [string]$DisplayTitle)

    # Switch Windows 11 to Picture mode (0)
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -Name BackgroundType -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value 10 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper  -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallPaper -Value $FilePath -ErrorAction SilentlyContinue

    $Definition = @"
using System;
using System.Runtime.InteropServices;
public class WinWallpaperApi {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
"@
    if (-not ([System.Management.Automation.PSTypeName]'WinWallpaperApi').Type) {
        Add-Type -TypeDefinition $Definition
    }

    $Spi = [WinWallpaperApi]::SystemParametersInfo(20, 0, $FilePath, 3)
    $NullOut = [UIntPtr]::Zero
    [WinWallpaperApi]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$NullOut) | Out-Null

    if ($Spi -eq 1) {
        Write-Host "Desktop wallpaper updated to: $DisplayTitle" -ForegroundColor Green
        return $true
    } else {
        Write-Warning "SystemParametersInfo returned failure code: $Spi"
        return $false
    }
}

if ($ExistingToday -and $ExistingToday.Length -gt 10000) {
    Write-Host "Today's wallpaper ($TodayTag) already cached locally. Applying..." -ForegroundColor Yellow
    [void](Apply-WallpaperFile -FilePath $ExistingToday.FullName -DisplayTitle $TodayTag)
    exit 0
}

# 3. Query Bing Public API
$ApiUrl = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=$Market"
$WebReq = [System.Net.HttpWebRequest]::Create($ApiUrl)
$WebReq.Timeout = 15000
$WebReq.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) BingDailyWallpaper/2.0"

try {
    $WebResp = $WebReq.GetResponse()
    $Stream = $WebResp.GetResponseStream()
    $Reader = New-Object System.IO.StreamReader($Stream)
    $RawJson = $Reader.ReadToEnd()
    $Reader.Close()
    $WebResp.Close()
    $Data = $RawJson | ConvertFrom-Json
    $ImageInfo = $Data.images[0]
} catch {
    Write-Warning "Failed to reach Bing API: $_"
    exit 1
}

if (-not $ImageInfo) {
    Write-Warning "No image data returned from Bing."
    exit 1
}

# 4. Strict Field Validation
$StartDate = "$($ImageInfo.startdate)".Trim()
if ($StartDate -notmatch '^\d{8}$') {
    Write-Warning "Invalid date format from API: $StartDate"
    exit 1
}

$Title     = "$($ImageInfo.title)".Trim()
$Copyright = "$($ImageInfo.copyright)".Trim()

# URL construction with hostname validation
function Resolve-BingUrl {
    param([string]$PathOrUrl)
    try {
        $Uri = [System.Uri]$PathOrUrl
        if ($Uri.IsAbsoluteUri) {
            if ($Uri.Host -ine "www.bing.com" -and $Uri.Host -ine "bing.com") { return $null }
            return $Uri.AbsoluteUri
        }
    } catch {}
    
    $Sanitized = "/" + ($PathOrUrl.TrimStart('/'))
    return "https://www.bing.com" + $Sanitized
}

$UhdCandidate = "$($ImageInfo.urlbase)_UHD.jpg"
$UhdUrl = Resolve-BingUrl $UhdCandidate
$StdUrl = Resolve-BingUrl $ImageInfo.url

$TargetFile = Join-Path -Path $SaveDir -ChildPath "Bing_$StartDate.jpg"
$MetaFile   = Join-Path -Path $SaveDir -ChildPath "Bing_$StartDate.json"

# Helper: check for JPEG magic bytes (FF D8 FF)
function Test-JpegFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $Bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($Bytes.Length -lt 4) { return $false }
        return ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF)
    } catch {
        return $false
    }
}

# 5. Atomic Download with validation
function Download-FileSafely {
    param([string]$SourceUrl, [string]$DestPath)
    if ([string]::IsNullOrWhiteSpace($SourceUrl)) { return $false }
    $TmpPath = $DestPath + ".tmp"
    try {
        $Client = New-Object System.Net.WebClient
        $Client.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) BingDailyWallpaper/2.0")
        $Client.DownloadFile($SourceUrl, $TmpPath)
        $Client.Dispose()

        if (Test-JpegFile $TmpPath) {
            Move-Item -LiteralPath $TmpPath -Destination $DestPath -Force
            return $true
        } else {
            Remove-Item -LiteralPath $TmpPath -Force -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        Remove-Item -LiteralPath $TmpPath -Force -ErrorAction SilentlyContinue
        return $false
    }
}

$Success = $false
if (-not (Test-Path -LiteralPath $TargetFile)) {
    Write-Host "Downloading today's Bing wallpaper: $Title" -ForegroundColor Cyan
    # Try 4K UHD first
    if ($UhdUrl) {
        $Success = Download-FileSafely -SourceUrl $UhdUrl -DestPath $TargetFile
        if ($Success) { Write-Host "Downloaded 4K UHD image successfully." -ForegroundColor Green }
    }
    # Fallback to standard resolution
    if (-not $Success -and $StdUrl) {
        $Success = Download-FileSafely -SourceUrl $StdUrl -DestPath $TargetFile
        if ($Success) { Write-Host "Downloaded 1080p image successfully." -ForegroundColor Green }
    }
} else {
    $Success = $true
}

if (-not $Success -or -not (Test-Path -LiteralPath $TargetFile)) {
    Write-Warning "Could not obtain valid wallpaper image."
    exit 1
}

# Write metadata
$Meta = [PSCustomObject]@{
    Date      = $StartDate
    Title     = $Title
    Copyright = $Copyright
    UhdUrl    = $UhdUrl
    StdUrl    = $StdUrl
} | ConvertTo-Json -Depth 2
Set-Content -LiteralPath $MetaFile -Value $Meta -Encoding UTF8

# 6. Apply Wallpaper
$Applied = Apply-WallpaperFile -FilePath $TargetFile -DisplayTitle "$Title ($StartDate)"
if (-not $Applied) { exit 1 }

# 7. Prune older files
try {
    $Cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -LiteralPath $SaveDir -Filter "Bing_*" | Where-Object {
        $_.LastWriteTime -lt $Cutoff
    } | Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}
