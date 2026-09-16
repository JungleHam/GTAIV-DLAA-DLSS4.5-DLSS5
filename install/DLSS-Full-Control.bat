@rem GTAIV-DLAA-DLSS4.5-DLSS5 quality, Neural Rendering, and launch helper.
@echo off
setlocal
set "DLSSF_CTL_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:DLSSF_CTL_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$Self = $env:DLSSF_CTL_SELF
$Game = Split-Path -Parent $Self
$Ini = Join-Path $Game '.trex\m3k-nr.ini'
$NrDll = Join-Path $Game '.trex\m3k\nvngx_dlssnr.dll'

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

function Set-DlssQuality([int]$Profile,[string]$Name) {
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { throw 'Close GTA IV before changing the saved DLSS quality mode.' }
    Set-Ini 'SRProfile' ([string]$Profile)
    Prepare-StartupStabilization
    Write-Host "Saved DLSS quality mode: $Name" -ForegroundColor Green
    Write-Host 'Next launch will use automatic startup stabilization, then switch to this mode.'
}

function Set-NeuralRendering([bool]$Enabled) {
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { throw 'Close GTA IV before changing Neural Rendering.' }
    if ($Enabled) {
        if (-not (Test-Path -LiteralPath $NrDll)) { throw "Missing $NrDll. Re-run Install-DLSS-Full.bat." }
        Set-Ini 'Mode' '2'
        Set-Ini 'NRPasses' '1'
        Write-Host 'DLSS 5 Neural Rendering: ON' -ForegroundColor Green
        Write-Host 'One Neural Rendering pass will run before DLSS Super Resolution.'
    } else {
        Set-Ini 'Mode' '0'
        Write-Host 'DLSS 5 Neural Rendering: OFF' -ForegroundColor Yellow
        Write-Host 'DLSS 4.5 Super Resolution remains enabled.'
    }
    Prepare-StartupStabilization
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

$names = @{ '1'='Custom Ultra Quality (77%)'; '2'='Quality'; '3'='Balanced'; '4'='Performance'; '5'='Ultra Performance' }
while ($true) {
    Clear-Host
    Write-Host '====================================================================' -ForegroundColor Cyan
    Write-Host ' GTA IV - DLSS 4.5 SUPER RESOLUTION + DLSS 5 NEURAL RENDERING' -ForegroundColor Cyan
    Write-Host '====================================================================' -ForegroundColor Cyan
    $p = Get-Ini 'SRProfile'
    $mode = Get-Ini 'Mode'
    $nr = if ($mode -eq '2') { 'ON' } elseif ($mode -eq '0') { 'OFF' } else { 'UNKNOWN' }
    Write-Host ("Saved DLSS quality: " + $(if ($names.ContainsKey($p)) { $names[$p] } else { $p }))
    Write-Host "Neural Rendering: $nr"
    Write-Host 'Startup stabilization: 1485x835 for 180 synchronized frames'
    Write-Host ''
    Write-Host 'DLSS 4.5 Super Resolution quality:'
    Write-Host '  [1] Custom Ultra Quality (77%)'
    Write-Host '  [2] Quality'
    Write-Host '  [3] Balanced'
    Write-Host '  [4] Performance'
    Write-Host '  [5] Ultra Performance'
    Write-Host ''
    Write-Host 'DLSS 5 Neural Rendering:'
    Write-Host '  [N] Turn Neural Rendering ON'
    Write-Host '  [O] Turn Neural Rendering OFF'
    Write-Host ''
    Write-Host '[L] Launch GTA IV with startup stabilization'
    Write-Host '[Q] Quit'
    Write-Host ''
    $choice = (Read-Host 'Choose').Trim()
    switch -Regex ($choice) {
        '^1$' { Set-DlssQuality 1 $names['1']; Read-Host 'Press Enter' | Out-Null }
        '^2$' { Set-DlssQuality 2 $names['2']; Read-Host 'Press Enter' | Out-Null }
        '^3$' { Set-DlssQuality 3 $names['3']; Read-Host 'Press Enter' | Out-Null }
        '^4$' { Set-DlssQuality 4 $names['4']; Read-Host 'Press Enter' | Out-Null }
        '^5$' { Set-DlssQuality 5 $names['5']; Read-Host 'Press Enter' | Out-Null }
        '^[Nn]$' { Set-NeuralRendering $true; Read-Host 'Press Enter' | Out-Null }
        '^[Oo]$' { Set-NeuralRendering $false; Read-Host 'Press Enter' | Out-Null }
        '^[Ll]$' { Launch-WithStartupStabilization; exit 0 }
        '^[Qq]$' { exit 0 }
    }
}
