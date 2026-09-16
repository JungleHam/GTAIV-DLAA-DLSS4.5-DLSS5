@rem GTAIV-DLAA-DLSS5 project installer. See docs/DLSS-FULL.md before use.
@echo off
setlocal
set "DLSSF_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:DLSSF_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Self = $env:DLSSF_SELF
$Game = Split-Path -Parent $Self
$Trex = Join-Path $Game '.trex'
$Temp = Join-Path $env:TEMP ("GTAIV_DLSS_FULL_" + $PID)
$Project = Join-Path $Temp 'project'
$BBridge = Join-Path $Temp 'bbridge'
$Venv = Join-Path $Temp 'venv'
$Checkpoint = '57a8bd2ede8d7b4b721b1981bc0e8a7e6cbe084f'
$BBridgeCommit = '1dad5e6d4dcf8647e354aa9a87f611256fb61142'
$ReferenceBridgeHash = '6DD40F145A5D503624E3E05ECF0ADBAA094CF83B24278C0BB333318E3C52A912'
$ReferenceFeederHash = 'C73D8D54271F55F8931F00D62A4CDF605118BEA71D7C6BEE0B61D0CA7C1CCE4B'
$ReferenceShimHash = 'A2E4BEDACE8D99BC60B5D18E958BD7E98F8887FF40EC45A8674B892E2D1FCBBC'
$TranscriptStarted = $false

function Fail([string]$Message) { throw $Message }

function Hash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '<missing>' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Write-NoBom([string]$Path,[string[]]$Lines) {
    [IO.File]::WriteAllLines($Path,$Lines,(New-Object Text.UTF8Encoding($false)))
}

function Copy-IfExists([string]$Source,[string]$Destination) {
    if (Test-Path -LiteralPath $Source) {
        $parent = Split-Path -Parent $Destination
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Set-KeyEquals([string]$Path,[string]$Key,[string]$Value) {
    $text = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
    $pat = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*.*$'
    $line = "$Key=$Value"
    if ($text -match $pat) { $text = [regex]::Replace($text,$pat,$line) }
    else {
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`r`n" }
        $text += $line + "`r`n"
    }
    [IO.File]::WriteAllText($Path,$text,(New-Object Text.UTF8Encoding($false)))
}

function Run([string]$Program,[string[]]$Arguments,[string]$Label) {
    Write-Host $Label -ForegroundColor Cyan
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { Fail "$Label failed with exit code $LASTEXITCODE" }
}

function Need-Command([string]$Name,[string]$Message) {
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $c) { Fail $Message }
    return $c.Source
}

Set-Location -LiteralPath $Game
$Log = Join-Path $Game 'DLSS_FULL_install.log'
try {
    Start-Transcript -LiteralPath $Log -Force | Out-Null
    $TranscriptStarted = $true

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' GTA IV DLSS FULL - A3-S2 + A3-S5' -ForegroundColor Green
    Write-Host ' DLAA baseline -> Super Resolution, NR remains OFF' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host "Game folder: $Game"
    Write-Host ''

    if (-not (Test-Path -LiteralPath (Join-Path $Game 'GTAIV.exe'))) { Fail 'Put this BAT beside GTAIV.exe.' }
    if (-not (Test-Path -LiteralPath $Trex)) { Fail 'Missing .trex. Install and verify the project DLAA module first.' }
    foreach ($required in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\nvngx_dlss.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Game $required))) { Fail "DLAA prerequisite missing: $required" }
    }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before installing DLSS Full.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before installing DLSS Full.' }

    $Git = Need-Command 'git.exe' 'Git for Windows is required for the reproducible DLSS Full build.'
    $Python = Need-Command 'python.exe' 'Python 3 in PATH is required for the reproducible DLSS Full build.'

    Write-Host 'Choose the saved DLSS Super Resolution mode:' -ForegroundColor Yellow
    Write-Host '  1 = Custom Ultra Quality (77%)'
    Write-Host '  2 = Quality [recommended default]'
    Write-Host '  3 = Balanced'
    Write-Host '  4 = Performance'
    Write-Host '  5 = Ultra Performance'
    $profile = (Read-Host 'Profile [2]').Trim()
    if (-not $profile) { $profile = '2' }
    if ($profile -notin @('1','2','3','4','5')) { Fail "Invalid profile: $profile" }

    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force }
    New-Item -ItemType Directory -Path $Temp -Force | Out-Null

    Run $Git @('clone','--filter=blob:none','https://github.com/JungleHam/GTAIV-DLAA-DLSS5.git',$Project) 'Cloning project source'
    Run $Git @('-C',$Project,'checkout',$Checkpoint) 'Checking out frozen A3-S5 checkpoint'
    $head = (& $Git -C $Project rev-parse HEAD).Trim()
    if ($head -ne $Checkpoint) { Fail "Wrong project revision: $head" }

    Write-Host ''
    Write-Host 'Building the A3-S5 Feeder chain from pinned sources...' -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Project 'tools\m3k-nr\build-a3-s5.ps1')
    if ($LASTEXITCODE -ne 0) { Fail "A3-S5 build failed with exit code $LASTEXITCODE" }

    $Feeder = Join-Path $Project 'tools\m3k-nr\out-m3k-a3-s5\dlss5-feed.addon64'
    $Shim = Join-Path $Project 'tools\m3k-nr\out-m3k-s27\m3k\m3k-nvngx.dll'
    if (-not (Test-Path -LiteralPath $Feeder)) { Fail 'A3-S5 Feeder output is missing.' }
    if (-not (Test-Path -LiteralPath $Shim)) { Fail 'Stable S2.7 shim output is missing.' }

    Write-Host ''
    Write-Host 'Building the accepted A3-S2 x86 b-bridge client...' -ForegroundColor Cyan
    Run $Git @('clone','--filter=blob:none','https://github.com/gutbash/b-bridge.git',$BBridge) 'Cloning pinned b-bridge source'
    Run $Git @('-C',$BBridge,'checkout',$BBridgeCommit) 'Checking out pinned b-bridge commit'
    Run $Git @('-C',$BBridge,'submodule','update','--init','--recursive') 'Preparing b-bridge submodules'
    $bhead = (& $Git -C $BBridge rev-parse HEAD).Trim()
    if ($bhead -ne $BBridgeCommit) { Fail "Wrong b-bridge revision: $bhead" }

    & $Python (Join-Path $Project 'tools\m3k-nr\a2-s21-bbridge-ui.py') $BBridge
    if ($LASTEXITCODE -ne 0) { Fail 'A3-S2 UI patch failed.' }
    & $Python (Join-Path $Project 'tools\m3k-nr\a3-s2-bbridge-coherent-draw-jitter.py') $BBridge
    if ($LASTEXITCODE -ne 0) { Fail 'A3-S2 coherent-jitter patch failed.' }
    & $Git -C $BBridge diff --check
    if ($LASTEXITCODE -ne 0) { Fail 'Patched b-bridge source failed git diff --check.' }

    Run $Python @('-m','venv',$Venv) 'Creating temporary Python build environment'
    $Vpy = Join-Path $Venv 'Scripts\python.exe'
    Run $Vpy @('-m','pip','install','--disable-pip-version-check','meson==0.64.1','ninja==1.11.1.1') 'Installing pinned Meson/Ninja build tools'
    $oldPath = $env:PATH
    $env:PATH = (Join-Path $Venv 'Scripts') + ';' + $env:PATH
    Push-Location $BBridge
    try {
        . .\build_common.ps1
        SetupVS -Platform x86
        & meson setup --buildtype release --backend ninja _compDLSSFull --debug
        if ($LASTEXITCODE -ne 0) { Fail "Meson setup failed: $LASTEXITCODE" }
        Copy-Item .\Directory.Build.Props -Destination .\_compDLSSFull -Force
        & meson compile -C _compDLSSFull d3d9
        if ($LASTEXITCODE -ne 0) { Fail "A3-S2 d3d9 build failed: $LASTEXITCODE" }
    } finally {
        Pop-Location
        $env:PATH = $oldPath
    }
    $Bridge = Join-Path $BBridge '_compDLSSFull\src\client\d3d9.dll'
    if (-not (Test-Path -LiteralPath $Bridge)) { Fail 'A3-S2 d3d9.dll output is missing.' }

    $bridgeHash = Hash $Bridge
    $feederHash = Hash $Feeder
    $shimHash = Hash $Shim
    Write-Host ''
    Write-Host 'Build outputs:' -ForegroundColor Cyan
    Write-Host "  d3d9.dll            $bridgeHash"
    Write-Host "  dlss5-feed.addon64  $feederHash"
    Write-Host "  m3k-nvngx.dll       $shimHash"
    if ($bridgeHash -eq $ReferenceBridgeHash) { Write-Host '  A3-S2 bridge matches the hardware-validated reference binary.' -ForegroundColor Green }
    else { Write-Host '  NOTE: A3-S2 bridge bytes differ from the CI reference (local compiler/toolchain), but pinned source + patch validation passed.' -ForegroundColor Yellow }
    if ($feederHash -eq $ReferenceFeederHash) { Write-Host '  A3-S5 Feeder matches the hardware-validated reference binary.' -ForegroundColor Green }
    else { Write-Host '  NOTE: A3-S5 Feeder bytes differ from the CI reference (local compiler/toolchain), but pinned source + CPU tests passed.' -ForegroundColor Yellow }
    if ($shimHash -eq $ReferenceShimHash) { Write-Host '  Stable S2.7 shim matches the hardware-validated reference binary.' -ForegroundColor Green }
    else { Write-Host '  NOTE: Stable shim bytes differ from the CI reference (local compiler/toolchain), but pinned S2.7 source + CPU tests passed.' -ForegroundColor Yellow }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Backup = Join-Path $Game ("_DLSS_FULL_PREINSTALL_BACKUP_" + $stamp)
    New-Item -ItemType Directory -Path $Backup -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Backup '.trex\m3k') -Force | Out-Null
    foreach ($rel in @('d3d9.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll')) {
        Copy-IfExists (Join-Path $Game $rel) (Join-Path $Backup $rel)
    }

    Write-Host ''
    Write-Host 'Installing DLSS Full runtime...' -ForegroundColor Cyan
    Copy-Item -LiteralPath $Bridge -Destination (Join-Path $Game 'd3d9.dll') -Force
    Copy-Item -LiteralPath $Feeder -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force
    New-Item -ItemType Directory -Path (Join-Path $Trex 'm3k') -Force | Out-Null
    Copy-Item -LiteralPath $Shim -Destination (Join-Path $Trex 'm3k\m3k-nvngx.dll') -Force

    $ini = @(
        '[M3K]',
        '; GTA IV DLSS Full - hardware-validated A3-S2 + A3-S5 path',
        '; Mode 0 keeps Neural Rendering disabled. Install NR separately later.',
        'Mode=0',
        'SourceProof=0',
        'SRProof=1',
        'RenderWidth=1485',
        'RenderHeight=835',
        'OutputWidth=0',
        'OutputHeight=0',
        'AutoResizeWindow=1',
        'VirtualizeGameClient=1',
        'NRPasses=1',
        "SRProfile=$profile",
        'ProjectionProbe=0',
        'TemporalJitter=1',
        'BalancedProbe=0',
        'ManualRender=0',
        'ManualRenderWidth=0',
        'ManualRenderHeight=0',
        'StartupPrime=1',
        'StartupPrimeWidth=1485',
        'StartupPrimeHeight=835',
        'StartupPrimeFrames=180'
    )
    Write-NoBom (Join-Path $Trex 'm3k-nr.ini') $ini

    $feedCfg = Join-Path $Trex 'dlss5-feed.cfg'
    Set-KeyEquals $feedCfg 'enabled' '1'
    Set-KeyEquals $feedCfg 'mode' '2'
    Set-KeyEquals $feedCfg 'work_resolution' '100'

    $controlUrl = 'https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS5/b78931d2069d0d38a2f2e7a38d8ed75ac889b071/install/DLSS-Full-Control.bat'
    $controlPath = Join-Path $Game 'DLSS-Full-Control.bat'
    Write-Host 'Installing DLSS-Full-Control.bat...' -ForegroundColor Cyan
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -L --fail --retry 3 --silent --show-error -o $controlPath $controlUrl
        if ($LASTEXITCODE -ne 0) { Fail 'Could not download DLSS-Full-Control.bat.' }
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $controlUrl -OutFile $controlPath
    }

    $receipt = @(
        'GTA IV DLSS FULL installation receipt',
        "Installed=$(Get-Date -Format o)",
        "ProjectCheckpoint=$Checkpoint",
        "BBridgeCommit=$BBridgeCommit",
        "SRProfile=$profile",
        'StartupPrime=1485x835',
        'StartupPrimeFrames=180',
        "d3d9.dll=$bridgeHash",
        "dlss5-feed.addon64=$feederHash",
        "m3k-nvngx.dll=$shimHash",
        "ReferenceA3S2Bridge=$ReferenceBridgeHash",
        "ReferenceA3S5Feeder=$ReferenceFeederHash",
        "ReferenceS27Shim=$ReferenceShimHash",
        "Backup=$Backup"
    )
    Write-NoBom (Join-Path $Game 'DLSS_FULL_INSTALLED.txt') $receipt

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' DLSS FULL INSTALLED' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host "Saved SRProfile: $profile"
    Write-Host 'Neural Rendering: OFF (Mode=0)'
    Write-Host 'Startup: 1485x835 prime -> 180 synchronized frames -> saved mode'
    Write-Host "Rollback backup: $Backup"
    Write-Host ''
    Write-Host 'Recommended launch: double-click DLSS-Full-Control.bat and choose L.' -ForegroundColor Yellow
    Write-Host 'Normal game launch also contains the A3-S5 primer, but the helper guarantees 1485x835 is written before GTA starts.'
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host 'INSTALL FAILED' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Log: $Log" -ForegroundColor Yellow
    exit 1
}
finally {
    if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
    if (Test-Path -LiteralPath $Temp) { try { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
}

exit 0
