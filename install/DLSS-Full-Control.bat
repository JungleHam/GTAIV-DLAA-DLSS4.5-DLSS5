@rem GTAIV-DLAA-DLSS5 DLSS Full profile/launch helper.
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

function Write-NoBom([string]$Path,[string[]]$Lines) {
    [IO.File]::WriteAllLines($Path,$Lines,(New-Object Text.UTF8Encoding($false)))
}

function Set-Ini([string]$Key,[string]$Value) {
    if (-not (Test-Path -LiteralPath $Ini)) { throw "Missing $Ini. Install DLSS Full first." }
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

function Arm-Prime {
    Set-Ini 'Mode' '0'
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

function Set-Profile([int]$Profile,[string]$Name) {
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { throw 'Close GTA IV before changing the saved startup profile.' }
    Set-Ini 'SRProfile' ([string]$Profile)
    Arm-Prime
    Write-Host "Saved DLSS mode: $Name" -ForegroundColor Green
    Write-Host 'Next launch will prime at 1485x835 and automatically switch to it.'
}

function Launch-Primed {
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { throw 'GTA IV is already running.' }
    Arm-Prime
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
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' GTA IV DLSS FULL' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    $p = Get-Ini 'SRProfile'
    Write-Host ("Saved mode: " + $(if ($names.ContainsKey($p)) { $names[$p] } else { $p }))
    Write-Host 'Startup prime: 1485x835 / 180 synchronized frames'
    Write-Host ''
    Write-Host '[1] Custom Ultra Quality (77%)'
    Write-Host '[2] Quality'
    Write-Host '[3] Balanced'
    Write-Host '[4] Performance'
    Write-Host '[5] Ultra Performance'
    Write-Host '[L] Launch GTA IV primed'
    Write-Host '[Q] Quit'
    Write-Host ''
    $choice = (Read-Host 'Choose').Trim()
    switch -Regex ($choice) {
        '^1$' { Set-Profile 1 $names['1']; Read-Host 'Press Enter' | Out-Null }
        '^2$' { Set-Profile 2 $names['2']; Read-Host 'Press Enter' | Out-Null }
        '^3$' { Set-Profile 3 $names['3']; Read-Host 'Press Enter' | Out-Null }
        '^4$' { Set-Profile 4 $names['4']; Read-Host 'Press Enter' | Out-Null }
        '^5$' { Set-Profile 5 $names['5']; Read-Host 'Press Enter' | Out-Null }
        '^[Ll]$' { Launch-Primed; exit 0 }
        '^[Qq]$' { exit 0 }
    }
}
