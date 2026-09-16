@rem GTAIV-DLAA-DLSS4.5-DLSS5 - roll DLSS Full back to the preserved DLAA + ReShade input-patch baseline.
@echo off
setlocal
set "DLSSU_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:DLSSU_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$Self = $env:DLSSU_SELF
$Game = Split-Path -Parent $Self
$Trex = Join-Path $Game '.trex'
$Log = Join-Path $Game 'DLSS_FULL_uninstall.log'
$TranscriptStarted = $false
$Safety = $null

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
$DlaaRequired = @(
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
    foreach ($rel in $DlaaRequired) { if (-not (Test-Path -LiteralPath (Join-Path $Path $rel))) { return $false } }
    foreach ($rel in $FullOnly) { if (Test-Path -LiteralPath (Join-Path $Path $rel)) { return $false } }
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
        Fail 'No trustworthy DLAA-only baseline snapshot was found. Nothing was changed. Reinstall the clean DLAA step before attempting removal.'
    }

    Write-Host "DLAA baseline selected: $Baseline" -ForegroundColor Cyan
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Safety = Join-Path $Game ("_DLSS_FULL_UNINSTALL_SAFETY_" + $stamp)
    Snapshot-Files $Safety
    Write-Host "Current DLSS Full runtime backed up to: $Safety" -ForegroundColor DarkGray

    Restore-RuntimeSnapshot $Baseline

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

    foreach ($rel in $DlaaRequired) {
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
    if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
}
exit 0
