@rem GTAIV-DLAA-DLSS4.5-DLSS5 launch, repair, and diagnostics helper.
@echo off
setlocal
set "DLSSF_CTL_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:DLSSF_CTL_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$Self = $env:DLSSF_CTL_SELF
$Game = Split-Path -Parent $Self
$Trex = Join-Path $Game '.trex'
$Ini = Join-Path $Trex 'm3k-nr.ini'
$Log = Join-Path $Trex 'dlss5-feed.log'
$NrDll = Join-Path $Trex 'm3k\nvngx_dlssnr.dll'
$Feeder = Join-Path $Trex 'dlss5-feed.addon64'

function Write-NoBom([string]$Path,[string[]]$Lines) {
    [IO.File]::WriteAllLines($Path,$Lines,(New-Object Text.UTF8Encoding($false)))
}

function Set-Ini([string]$Key,[string]$Value) {
    if (-not (Test-Path -LiteralPath $Ini)) { throw "Missing $Ini. Install Step 4 first." }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($x in @(Get-Content -LiteralPath $Ini)) { [void]$lines.Add([string]$x) }
    $found = $false
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $lines[$i] = "$Key=$Value"; $found = $true; break
        }
    }
    if (-not $found) { [void]$lines.Add("$Key=$Value") }
    Write-NoBom $Ini $lines.ToArray()
}

function Get-Ini([string]$Key) {
    if (-not (Test-Path -LiteralPath $Ini)) { return '<missing>' }
    $m = Select-String -LiteralPath $Ini -Pattern ('^\s*' + [regex]::Escape($Key) + '\s*=(.*)$') | Select-Object -Last 1
    if ($m) { return $m.Matches[0].Groups[1].Value.Trim() }
    return '<unset>'
}

function Prepare-StartupStabilization {
    Set-Ini 'SRProof' '1'
    Set-Ini 'RenderWidth' '1485'
    Set-Ini 'RenderHeight' '835'
    Set-Ini 'AutoResizeWindow' '1'
    Set-Ini 'VirtualizeGameClient' '1'
    Set-Ini 'TemporalJitter' '1'
    Set-Ini 'StartupPrime' '1'
    Set-Ini 'StartupPrimeWidth' '1485'
    Set-Ini 'StartupPrimeHeight' '835'
    Set-Ini 'StartupPrimeFrames' '180'
    Set-Ini 'ManualRender' '0'
    Set-Ini 'BalancedProbe' '0'
}

function Show-Status {
    $names = @{ '1'='Custom Ultra Quality (77%)'; '2'='Quality'; '3'='Balanced'; '4'='Performance'; '5'='Ultra Performance' }
    $p = Get-Ini 'SRProfile'
    $mode = Get-Ini 'Mode'
    $passes = Get-Ini 'NRPasses'
    $nr = if ($mode -eq '2') { 'ON' } elseif ($mode -eq '0') { 'OFF' } else { "UNKNOWN ($mode)" }
    Write-Host ''
    Write-Host 'Current settings' -ForegroundColor Cyan
    Write-Host ('  DLSS quality:        ' + $(if ($names.ContainsKey($p)) { $names[$p] } else { $p }))
    Write-Host "  Neural Rendering:    $nr"
    Write-Host "  NR passes:           $passes"
    Write-Host '  Startup stabilization: 1485x835 / 180 synchronized frames'
    Write-Host ''
    Write-Host 'Runtime files' -ForegroundColor Cyan
    Write-Host ('  Feeder:              ' + $(if (Test-Path -LiteralPath $Feeder) { 'present' } else { 'MISSING' }))
    Write-Host ('  Neural Rendering DLL:' + $(if (Test-Path -LiteralPath $NrDll) { ' present' } else { ' MISSING' }))
    Write-Host ('  Log:                 ' + $(if (Test-Path -LiteralPath $Log) { 'present' } else { 'not created yet' }))
    Write-Host ''
    Write-Host 'Change DLSS quality and Neural Rendering in-game:' -ForegroundColor Yellow
    Write-Host '  Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS'
}

function Repair-StartupStabilization {
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { throw 'Close GTA IV before repairing startup settings.' }
    Prepare-StartupStabilization
    Write-Host 'Startup stabilization settings restored.' -ForegroundColor Green
    Write-Host 'DLSS quality, Neural Rendering state, and NR pass count were preserved.'
}

function Launch-WithStartupStabilization {
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { throw 'GTA IV is already running.' }
    Prepare-StartupStabilization
    $play = Join-Path $Game 'PlayGTAIV.exe'
    if (Test-Path -LiteralPath $play) {
        Start-Process -FilePath $play
    } else {
        Start-Process 'steam://rungameid/12210'
    }
}

function Open-DiagnosticLog {
    if (-not (Test-Path -LiteralPath $Log)) { throw "Log not found yet: $Log" }
    Start-Process notepad.exe -ArgumentList @($Log)
}

while ($true) {
    Clear-Host
    Write-Host '====================================================================' -ForegroundColor Cyan
    Write-Host ' GTA IV - DLSS TOOLS' -ForegroundColor Cyan
    Write-Host ' Launch / repair / diagnostics only' -ForegroundColor Cyan
    Write-Host '====================================================================' -ForegroundColor Cyan
    Write-Host 'DLSS quality and Neural Rendering are controlled inside ReShade.'
    Write-Host 'Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS'
    Write-Host ''
    Write-Host '[L] Launch GTA IV with startup stabilization'
    Write-Host '[R] Repair / re-arm startup stabilization settings'
    Write-Host '[S] Show current DLSS / Neural Rendering status'
    Write-Host '[D] Open DLSS diagnostic log'
    Write-Host '[Q] Quit'
    Write-Host ''
    $choice = (Read-Host 'Choose').Trim()
    switch -Regex ($choice) {
        '^[Ll]$' { Launch-WithStartupStabilization; exit 0 }
        '^[Rr]$' { Repair-StartupStabilization; Read-Host 'Press Enter' | Out-Null }
        '^[Ss]$' { Show-Status; Read-Host 'Press Enter' | Out-Null }
        '^[Dd]$' { Open-DiagnosticLog; Read-Host 'Press Enter' | Out-Null }
        '^[Qq]$' { exit 0 }
    }
}
