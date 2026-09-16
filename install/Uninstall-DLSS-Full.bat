@rem GTAIV-DLAA-DLSS4.5-DLSS5 - roll DLSS Full back to the preserved DLAA + ReShade input-patch baseline.
@echo off
setlocal
set "DLSSU_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:DLSSU_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Self = $env:DLSSU_SELF
$Game = Split-Path -Parent $Self
$Trex = Join-Path $Game '.trex'
$Log = Join-Path $Game 'DLSS_FULL_uninstall.log'
$Temp = Join-Path $env:TEMP ("GTAIV_DLSS_FULL_UNINSTALL_" + $PID)
$TranscriptStarted = $false
$Safety = $null
$BBridgePackageUrl = 'https://github.com/gutbash/b-bridge/releases/download/v0.1.0/b-bridge-0.1.0.zip'
$BBridgePackageHash = 'D5691AD68CCA6E731BBE12B34B14B6A8288E2E7E319E8EF0E13E0F3A59C31C55'

function Fail([string]$Message) { throw $Message }

$RuntimeFiles = @(
    'd3d9.dll',
    '.trex\NvRemixBridge.exe',
    '.trex\d3d9vk_x64.dll',
    '.trex\dlss5-feed.addon64',
    '.trex\dlss5-feed.cfg',
    '.trex\m3k-nr.ini',
    '.trex\m3k\m3k-nvngx.dll',
    '.trex\m3k\nvngx_dlssnr.dll'
)
# Old Full installers (before the public presenter packaging fix) did not copy
# d3d9vk_x64.dll into their preinstall backup. These four files are enough to
# identify the original DLAA-only runtime; the missing stock presenter can be
# reconstructed from the exact pinned b-bridge 0.1.0 package.
$DlaaBaselineCore = @(
    'd3d9.dll',
    '.trex\NvRemixBridge.exe',
    '.trex\dlss5-feed.addon64',
    '.trex\dlss5-feed.cfg'
)
$DlaaRequiredAfterRestore = @(
    'd3d9.dll',
    '.trex\NvRemixBridge.exe',
    '.trex\d3d9vk_x64.dll',
    '.trex\dlss5-feed.addon64',
    '.trex\dlss5-feed.cfg'
)
$FullOnly = @(
    '.trex\m3k-nr.ini',
    '.trex\m3k\m3k-nvngx.dll',
    '.trex\m3k\nvngx_dlssnr.dll'
)

function Hash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '<missing>' }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $bytes = $sha.ComputeHash($stream) }
        finally { $sha.Dispose() }
    } finally {
        $stream.Dispose()
    }
    return ([BitConverter]::ToString($bytes)).Replace('-','')
}

function Assert-SHA256([string]$Path,[string]$Expected) {
    $actual = Hash $Path
    if ($actual -ne $Expected.ToUpperInvariant()) {
        Fail "SHA256 mismatch for $Path`nExpected: $Expected`nActual:   $actual"
    }
}

function Download-File([string]$Url,[string]$Dest) {
    Write-Host "Downloading: $Url" -ForegroundColor Cyan
    Write-Host "  Temporary file: $Dest" -ForegroundColor DarkGray
    Write-Host '  This download will be deleted automatically after use, including if uninstall fails.' -ForegroundColor DarkGray
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -L --fail --retry 3 --connect-timeout 20 --silent --show-error -o $Dest $Url
        if ($LASTEXITCODE -ne 0) { Fail "Download failed: $Url" }
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
    }
    if (-not (Test-Path -LiteralPath $Dest)) { Fail "Downloaded file is missing: $Dest" }
}

function Remove-TemporaryFiles {
    if (-not (Test-Path -LiteralPath $Temp)) { return }
    Write-Host "Cleaning temporary uninstaller files: $Temp" -ForegroundColor DarkGray
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction Stop
            Write-Host 'Temporary uninstaller files deleted.' -ForegroundColor DarkGray
            return
        } catch {
            if ($attempt -lt 3) { Start-Sleep -Milliseconds 300 }
            else { Write-Host ("WARNING: Could not completely remove temporary uninstaller folder: " + $_.Exception.Message) -ForegroundColor Yellow }
        }
    }
}

function Copy-IfExists([string]$Source,[string]$Destination) {
    if (Test-Path -LiteralPath $Source) {
        $parent = Split-Path -Parent $Destination
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Snapshot-Files([string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($rel in $RuntimeFiles) { Copy-IfExists (Join-Path $Game $rel) (Join-Path $Destination $rel) }
    foreach ($rel in @('DLSS-Full-Control.bat','DLSS_FULL_INSTALLED.txt')) { Copy-IfExists (Join-Path $Game $rel) (Join-Path $Destination $rel) }
}

function Test-DlaaBaseline([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    foreach ($rel in $DlaaBaselineCore) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $rel))) { return $false }
    }
    foreach ($rel in $FullOnly) {
        if (Test-Path -LiteralPath (Join-Path $Path $rel)) { return $false }
    }
    return $true
}

function Restore-RuntimeSnapshot([string]$Path) {
    foreach ($rel in $RuntimeFiles) {
        $dst = Join-Path $Game $rel
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue }
        $src = Join-Path $Path $rel
        if (Test-Path -LiteralPath $src) {
            $parent = Split-Path -Parent $dst
            if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}

function Restore-StockDlaaPresenterIfMissing([string]$Baseline) {
    $dst = Join-Path $Trex 'd3d9vk_x64.dll'
    $baselinePresenter = Join-Path $Baseline '.trex\d3d9vk_x64.dll'
    if (Test-Path -LiteralPath $baselinePresenter) {
        if (-not (Test-Path -LiteralPath $dst)) {
            Copy-Item -LiteralPath $baselinePresenter -Destination $dst -Force
        }
        return
    }

    Write-Host ''
    Write-Host 'Legacy DLAA backup detected: it predates d3d9vk_x64.dll backup support.' -ForegroundColor Yellow
    Write-Host 'Restoring the original stock DLAA presenter from pinned b-bridge 0.1.0...' -ForegroundColor Cyan

    Remove-TemporaryFiles
    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    Write-Host "Temporary download/work folder: $Temp" -ForegroundColor DarkGray
    Write-Host 'Everything downloaded or extracted here will be deleted automatically after use, including if uninstall fails.' -ForegroundColor DarkGray

    $zip = Join-Path $Temp 'b-bridge-0.1.0.zip'
    $extract = Join-Path $Temp 'b-bridge'
    Download-File $BBridgePackageUrl $zip
    Assert-SHA256 $zip $BBridgePackageHash
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force

    $bridgeClient = Get-ChildItem -LiteralPath $extract -Filter 'd3d9.dll' -File -Recurse |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.Directory.FullName '.trex\NvRemixBridge.exe') } |
        Select-Object -First 1
    if (-not $bridgeClient) { Fail 'Could not locate the pinned b-bridge 0.1.0 GTA IV payload.' }

    $stockPresenter = Join-Path $bridgeClient.Directory.FullName '.trex\d3d9vk_x64.dll'
    if (-not (Test-Path -LiteralPath $stockPresenter)) {
        Fail 'Pinned b-bridge 0.1.0 package is missing .trex\d3d9vk_x64.dll.'
    }
    Copy-Item -LiteralPath $stockPresenter -Destination $dst -Force
    Write-Host 'Original DLAA DXVK presenter restored from pinned b-bridge 0.1.0.' -ForegroundColor Green
}

try {
    Start-Transcript -LiteralPath $Log -Force | Out-Null
    $TranscriptStarted = $true
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' GTA IV - UNINSTALL DLSS FULL -> RESTORE DLAA BASELINE' -ForegroundColor Green
    Write-Host ' ReShade input patch / FusionFix / DLSS 4.5 DLAA stay installed' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host "Game folder: $Game"

    if (-not (Test-Path -LiteralPath (Join-Path $Game 'GTAIV.exe'))) { Fail 'Put this BAT beside GTAIV.exe.' }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before uninstalling DLSS Full.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before uninstalling DLSS Full.' }

    $Baseline = Join-Path $Game '_DLSS_FULL_DLAA_BASELINE'
    if (-not (Test-DlaaBaseline $Baseline)) {
        $Baseline = $null
        $candidates = @(Get-ChildItem -LiteralPath $Game -Directory -Filter '_DLSS_FULL_PREINSTALL_BACKUP_*' -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($candidate in $candidates) {
            if (Test-DlaaBaseline $candidate.FullName) { $Baseline = $candidate.FullName; break }
        }
    }
    if (-not $Baseline) {
        Fail 'No trustworthy DLAA-only baseline snapshot was found. Nothing was changed. The expected older backup must contain the DLAA bridge client/server, Feeder add-on and Feeder config and must not contain DLSS Full-only M3K/NR files.'
    }

    $legacyBaseline = -not (Test-Path -LiteralPath (Join-Path $Baseline '.trex\d3d9vk_x64.dll'))
    Write-Host "DLAA baseline selected: $Baseline" -ForegroundColor Cyan
    if ($legacyBaseline) {
        Write-Host 'Baseline format: legacy (stock DXVK presenter will be reconstructed from pinned b-bridge 0.1.0).' -ForegroundColor Yellow
    } else {
        Write-Host 'Baseline format: complete.' -ForegroundColor DarkGray
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Safety = Join-Path $Game ("_DLSS_FULL_UNINSTALL_SAFETY_" + $stamp)
    Snapshot-Files $Safety
    Write-Host "Current DLSS Full runtime backed up to: $Safety" -ForegroundColor DarkGray

    Restore-RuntimeSnapshot $Baseline
    Restore-StockDlaaPresenterIfMissing $Baseline

    foreach ($rel in $FullOnly) {
        $p = Join-Path $Game $rel
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    $m3kDir = Join-Path $Trex 'm3k'
    if (Test-Path -LiteralPath $m3kDir) {
        $remaining = @(Get-ChildItem -LiteralPath $m3kDir -Force -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) { Remove-Item -LiteralPath $m3kDir -Force }
    }
    foreach ($rel in @('DLSS-Full-Control.bat','DLSS_FULL_INSTALLED.txt')) {
        $p = Join-Path $Game $rel
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }

    foreach ($rel in $DlaaRequiredAfterRestore) {
        if (-not (Test-Path -LiteralPath (Join-Path $Game $rel))) { Fail "DLAA restore validation failed: missing $rel" }
    }
    foreach ($rel in $FullOnly) {
        if (Test-Path -LiteralPath (Join-Path $Game $rel)) { Fail "DLSS Full removal validation failed: still present $rel" }
    }

    Write-Host ''
    Write-Host 'SUCCESS: DLSS Full removed; DLAA-only runtime restored.' -ForegroundColor Green
    Write-Host 'FusionFix, ReShade, the ReShade input patch, LumeniteFX and nvngx_dlss.dll were left in place.' -ForegroundColor Green
    Write-Host 'Launch GTA IV normally and verify DLAA before reinstalling DLSS Full.' -ForegroundColor Yellow
    Write-Host "Safety backup of the removed Full runtime: $Safety" -ForegroundColor DarkGray
    Write-Host "Log: $Log" -ForegroundColor DarkGray
}
catch {
    $msg = $_.Exception.Message
    Write-Host ''
    Write-Host 'UNINSTALL FAILED' -ForegroundColor Red
    Write-Host $msg -ForegroundColor Red
    if ($Safety -and (Test-Path -LiteralPath $Safety)) {
        Write-Host 'Attempting to restore the pre-uninstall DLSS Full runtime...' -ForegroundColor Yellow
        try {
            Restore-RuntimeSnapshot $Safety
            Copy-IfExists (Join-Path $Safety 'DLSS-Full-Control.bat') (Join-Path $Game 'DLSS-Full-Control.bat')
            Copy-IfExists (Join-Path $Safety 'DLSS_FULL_INSTALLED.txt') (Join-Path $Game 'DLSS_FULL_INSTALLED.txt')
            Write-Host 'Pre-uninstall runtime restored where possible.' -ForegroundColor Green
        } catch { Write-Host ('Rollback error: ' + $_.Exception.Message) -ForegroundColor Red }
    }
    Write-Host "Log: $Log" -ForegroundColor Yellow
    exit 1
}
finally {
    Remove-TemporaryFiles
    if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
}
exit 0
