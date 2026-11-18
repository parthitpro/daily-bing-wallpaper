#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads and applies the daily Bing 4K UHD wallpaper on Windows.
.DESCRIPTION
    Hardened daily Bing wallpaper automation conforming to FINAL_AUDIT standards:
    - 18-hour cache check with full JPEG header + EOF trailer verification.
    - Full [Uri] host pinning & parameter URL encoding.
    - Process-isolated atomic download (.PID.tmp) with finally-block stream disposal.
    - Connection + ReadWrite timeouts on all network calls.
    - Strict date parse validation.
    - Verified Windows 11 BackgroundType registry read-back.
    - Win32 SystemParametersInfo status verification with Explorer broadcast.
    - Validated retention pruning range.
#>

[CmdletBinding()]
param(
    [string]$Market = "auto",
    [ValidateRange(1, 365)][int]$RetentionDays = 30
)

# Enforce TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. Establish Directories (P3-1: fallback to $env:USERPROFILE if MyPictures empty)
$PicturesDir = [Environment]::GetFolderPath('MyPictures')
if ([string]::IsNullOrWhiteSpace($PicturesDir)) {
    $PicturesDir = Join-Path -Path $env:USERPROFILE -ChildPath 'Pictures'
}
$SaveDir = Join-Path -Path $PicturesDir -ChildPath 'BingWallpapers'
if (-not (Test-Path -LiteralPath $SaveDir)) {
    New-Item -ItemType Directory -Path $SaveDir -Force | Out-Null
}

# Helper: Test for complete JPEG file (magic bytes FF D8 FF and EOF trailer FF D9) (P3-3)
function Test-JpegFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $Bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($Bytes.Length -lt 4) { return $false }
        $ValidHeader = ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF)
        $ValidTrailer = ($Bytes[$Bytes.Length - 2] -eq 0xFF -and $Bytes[$Bytes.Length - 1] -eq 0xD9)
        return ($ValidHeader -and $ValidTrailer)
    } catch {
        return $false
    }
}

function Apply-WallpaperFile {
    param([string]$FilePath, [string]$DisplayTitle)

    # Switch Windows 11 to Picture mode (0)
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -Name BackgroundType -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value 10 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper  -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallPaper -Value $FilePath -ErrorAction SilentlyContinue

    # Verify BackgroundType read-back (P2-5)
    try {
        $Bg = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -Name BackgroundType -ErrorAction SilentlyContinue).BackgroundType
        if ($null -ne $Bg -and $Bg -ne 0) {
            Write-Warning "Could not switch Windows out of Spotlight mode. Current mode: $Bg"
            return $false
        }
    } catch {}

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

# 2. Check for recent cache (files modified within the last 18 hours)
$RecentFiles = @(Get-ChildItem -LiteralPath $SaveDir -Filter "Bing_*.jpg" -ErrorAction SilentlyContinue | Where-Object {
    $_.LastWriteTime -gt (Get-Date).AddHours(-18)
} | Sort-Object LastWriteTime -Descending)

if ($RecentFiles.Count -gt 0) {
    $Cached = $RecentFiles[0]
    if (Test-JpegFile $Cached.FullName) {
        Write-Host "Recent wallpaper ($($Cached.Name)) already cached. Applying..." -ForegroundColor Yellow
        $Ok = Apply-WallpaperFile -FilePath $Cached.FullName -DisplayTitle $Cached.Name
        if ($Ok) { exit 0 } else { exit 1 }
    }
}

# 3. Query Bing Public API with URL-encoding and ReadWriteTimeout (P3-2, P3-5)
$ApiUrl = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=" + [Uri]::EscapeDataString($Market)
$WebReq = [System.Net.HttpWebRequest]::Create($ApiUrl)
$WebReq.Timeout = 15000
$WebReq.ReadWriteTimeout = 15000
$WebReq.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) BingDailyWallpaper/2.1"

$WebResp = $null
$Stream = $null
$Reader = $null
try {
    $WebResp = $WebReq.GetResponse()
    if ($WebResp.ContentType -notmatch 'json') {
        Write-Warning "Unexpected Bing API content type: $($WebResp.ContentType)"
        exit 1
    }
    $Stream = $WebResp.GetResponseStream()
    $Reader = New-Object System.IO.StreamReader($Stream)
    $RawJson = $Reader.ReadToEnd()
    $Data = $RawJson | ConvertFrom-Json
    $ImageInfo = $Data.images[0]
} catch {
    Write-Warning "Failed to reach Bing API: $_"
    exit 1
} finally {
    if ($Reader)  { $Reader.Dispose() }
    if ($Stream)  { $Stream.Dispose() }
    if ($WebResp) { $WebResp.Dispose() }
}

if (-not $ImageInfo) {
    Write-Warning "No image data returned from Bing."
    exit 1
}

# 4. Strict Date & URL Validation (P4-3: DateTime exact parse)
$StartDate = "$($ImageInfo.startdate)".Trim()
$ParsedDate = [DateTime]::MinValue
if (-not [DateTime]::TryParseExact($StartDate, "yyyyMMdd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ParsedDate)) {
    Write-Warning "Invalid date format from Bing API: $StartDate"
    exit 1
}

$Title     = "$($ImageInfo.title)".Trim()
$Copyright = "$($ImageInfo.copyright)".Trim()

function Resolve-BingUrl {
    param([string]$PathOrUrl = '')
    if ([string]::IsNullOrWhiteSpace($PathOrUrl)) { return $null }
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

# 5. Atomic Download with unique PID temp file, ReadWriteTimeout, and full validation (P1-1, P3-3, P3-4, P3-5, P3-7)
function Download-FileSafely {
    param([string]$SourceUrl, [string]$DestPath)
    if ([string]::IsNullOrWhiteSpace($SourceUrl)) { return $false }
    $TmpPath = $DestPath + ".$PID.tmp"
    $Req = [System.Net.HttpWebRequest]::Create($SourceUrl)
    $Req.Timeout = 20000
    $Req.ReadWriteTimeout = 20000
    $Req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) BingDailyWallpaper/2.1"

    $Resp = $null
    $RespStream = $null
    $FileStream = $null
    try {
        $Resp = $Req.GetResponse()
        $RespStream = $Resp.GetResponseStream()
        $FileStream = [System.IO.File]::Create($TmpPath)
        $RespStream.CopyTo($FileStream)
        $FileStream.Flush()
        $FileStream.Close()
        $FileStream = $null

        if (Test-JpegFile -Path $TmpPath) {
            Move-Item -LiteralPath $TmpPath -Destination $DestPath -Force
            return $true
        } else {
            Remove-Item -LiteralPath $TmpPath -Force -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        return $false
    } finally {
        if ($FileStream) { $FileStream.Dispose() }
        if ($RespStream) { $RespStream.Dispose() }
        if ($Resp)       { $Resp.Dispose() }
        if (Test-Path -LiteralPath $TmpPath) {
            Remove-Item -LiteralPath $TmpPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# P1-1: Validate existing target if present; re-download if corrupt
$Success = $false
if (Test-Path -LiteralPath $TargetFile) {
    if (Test-JpegFile -Path $TargetFile) {
        $Success = $true
    } else {
        Write-Warning "Existing target file is corrupt. Re-downloading..."
        Remove-Item -LiteralPath $TargetFile -Force -ErrorAction SilentlyContinue
    }
}

if (-not $Success) {
    Write-Host "Downloading today's Bing wallpaper: $Title" -ForegroundColor Cyan
    if ($UhdUrl) {
        $Success = Download-FileSafely -SourceUrl $UhdUrl -DestPath $TargetFile
        if ($Success) { Write-Host "Downloaded 4K UHD image successfully." -ForegroundColor Green }
    }
    if (-not $Success -and $StdUrl) {
        $Success = Download-FileSafely -SourceUrl $StdUrl -DestPath $TargetFile
        if ($Success) { Write-Host "Downloaded 1080p image successfully." -ForegroundColor Green }
    }
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

# 7. Prune older files (P3-6: ValidateRange on param)
try {
    $Cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -LiteralPath $SaveDir -Filter "Bing_*" | Where-Object {
        $_.LastWriteTime -lt $Cutoff
    } | Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}
