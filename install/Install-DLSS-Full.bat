@rem GTAIV-DLAA-DLSS4.5-DLSS5 combined SR + NR installer. See docs/DLSS-FULL.md before use.
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
$RepoUrl = 'https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5.git'
$ReferenceBridgeHash = '6DD40F145A5D503624E3E05ECF0ADBAA094CF83B24278C0BB333318E3C52A912'
$ReferenceFeederHash = 'C73D8D54271F55F8931F00D62A4CDF605118BEA71D7C6BEE0B61D0CA7C1CCE4B'
$ReferenceShimHash = 'A2E4BEDACE8D99BC60B5D18E958BD7E98F8887FF40EC45A8674B892E2D1FCBBC'
$NrPackageUrl = 'https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0-RTX40/nvngx_dlssnr_310.8.0-RTX40.zip'
$NrPackageHash = '46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F'
$NrDllHash = '4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05'
$TranscriptStarted = $false

function Fail([string]$Message) { throw $Message }

function Hash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '<missing>' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Assert-SHA256([string]$Path,[string]$Expected) {
    $actual = Hash $Path
    if ($actual -ne $Expected.ToUpperInvariant()) {
        Fail "SHA256 mismatch for $Path`nExpected: $Expected`nActual:   $actual"
    }
}

function Download-File([string]$Url,[string]$Dest) {
    Write-Host "Downloading: $Url" -ForegroundColor Cyan
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -L --fail --retry 3 --connect-timeout 20 --silent --show-error -o $Dest $Url
        if ($LASTEXITCODE -ne 0) { Fail "Download failed: $Url" }
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
    }
    if (-not (Test-Path -LiteralPath $Dest)) { Fail "Downloaded file is missing: $Dest" }
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
    Write-Host '====================================================================' -ForegroundColor Green
    Write-Host ' GTA IV - DLSS 4.5 SUPER RESOLUTION + DLSS 5 NEURAL RENDERING' -ForegroundColor Green
    Write-Host ' Temporal synchronization + automatic startup stabilization' -ForegroundColor Green
    Write-Host ' Neural Rendering is installed but remains OFF by default' -ForegroundColor Green
    Write-Host '====================================================================' -ForegroundColor Green
    Write-Host "Game folder: $Game"
    Write-Host ''

    if (-not (Test-Path -LiteralPath (Join-Path $Game 'GTAIV.exe'))) { Fail 'Put this BAT beside GTAIV.exe.' }
    if (-not (Test-Path -LiteralPath $Trex)) { Fail 'Missing .trex. Complete the DLAA step first.' }
    foreach ($required in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\nvngx_dlss.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Game $required))) { Fail "DLAA prerequisite missing: $required" }
    }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before installing the combined module.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before installing the combined module.' }

    $Git = Need-Command 'git.exe' 'Git for Windows is required for the reproducible combined-module build.'
    $Python = Need-Command 'python.exe' 'Python 3 in PATH is required for the reproducible combined-module build.'

    Write-Host 'Choose the saved DLSS 4.5 Super Resolution quality mode:' -ForegroundColor Yellow
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

    Write-Host ''
    Write-Host 'Downloading the tested DLSS 5 Neural Rendering runtime for RTX 40/50...' -ForegroundColor Cyan
    $nrZip = Join-Path $Temp 'nvngx_dlssnr_310.8.0-RTX40.zip'
    $nrDir = Join-Path $Temp 'dlssnr'
    Download-File $NrPackageUrl $nrZip
    Assert-SHA256 $nrZip $NrPackageHash
    Expand-Archive -LiteralPath $nrZip -DestinationPath $nrDir -Force
    $NrDll = Get-ChildItem -LiteralPath $nrDir -Filter 'nvngx_dlssnr.dll' -File -Recurse | Select-Object -First 1
    if (-not $NrDll) { Fail 'nvngx_dlssnr.dll was not found in the pinned NR package.' }
    Assert-SHA256 $NrDll.FullName $NrDllHash

    Run $Git @('clone','--filter=blob:none',$RepoUrl,$Project) 'Cloning project source'
    Run $Git @('-C',$Project,'checkout',$Checkpoint) 'Checking out the frozen tested project checkpoint'
    $head = (& $Git -C $Project rev-parse HEAD).Trim()
    if ($head -ne $Checkpoint) { Fail "Wrong project revision: $head" }

    Write-Host ''
    Write-Host 'Building the tested DLSS integration from pinned sources...' -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Project 'tools\m3k-nr\build-a3-s5.ps1')
    if ($LASTEXITCODE -ne 0) { Fail "DLSS integration build failed with exit code $LASTEXITCODE" }

    $Feeder = Join-Path $Project 'tools\m3k-nr\out-m3k-a3-s5\dlss5-feed.addon64'
    $Shim = Join-Path $Project 'tools\m3k-nr\out-m3k-s27\m3k\m3k-nvngx.dll'
    if (-not (Test-Path -LiteralPath $Feeder)) { Fail 'DLSS integration Feeder output is missing.' }
    if (-not (Test-Path -LiteralPath $Shim)) { Fail 'DLSS integration shim output is missing.' }

    Write-Host ''
    Write-Host 'Building the tested temporal-synchronization bridge...' -ForegroundColor Cyan
    Run $Git @('clone','--filter=blob:none','https://github.com/gutbash/b-bridge.git',$BBridge) 'Cloning pinned b-bridge source'
    Run $Git @('-C',$BBridge,'checkout',$BBridgeCommit) 'Checking out pinned b-bridge commit'
    Run $Git @('-C',$BBridge,'submodule','update','--init','--recursive') 'Preparing b-bridge submodules'
    $bhead = (& $Git -C $BBridge rev-parse HEAD).Trim()
    if ($bhead -ne $BBridgeCommit) { Fail "Wrong b-bridge revision: $bhead" }

    & $Python (Join-Path $Project 'tools\m3k-nr\a2-s21-bbridge-ui.py') $BBridge
    if ($LASTEXITCODE -ne 0) { Fail 'Bridge window/resolution patch failed.' }
    & $Python (Join-Path $Project 'tools\m3k-nr\a3-s2-bbridge-coherent-draw-jitter.py') $BBridge
    if ($LASTEXITCODE -ne 0) { Fail 'Temporal-synchronization patch failed.' }
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
        if ($LASTEXITCODE -ne 0) { Fail "Temporal-synchronization bridge build failed: $LASTEXITCODE" }
    } finally {
        Pop-Location
        $env:PATH = $oldPath
    }
    $Bridge = Join-Path $BBridge '_compDLSSFull\src\client\d3d9.dll'
    if (-not (Test-Path -LiteralPath $Bridge)) { Fail 'Temporal-synchronization bridge d3d9.dll output is missing.' }

    $bridgeHash = Hash $Bridge
    $feederHash = Hash $Feeder
    $shimHash = Hash $Shim
    Write-Host ''
    Write-Host 'Build/runtime outputs:' -ForegroundColor Cyan
    Write-Host "  d3d9.dll             $bridgeHash"
    Write-Host "  dlss5-feed.addon64   $feederHash"
    Write-Host "  m3k-nvngx.dll        $shimHash"
    Write-Host "  nvngx_dlssnr.dll     $NrDllHash"
    if ($bridgeHash -eq $ReferenceBridgeHash) { Write-Host '  Temporal-synchronization bridge matches the hardware-tested reference binary.' -ForegroundColor Green }
    else { Write-Host '  NOTE: bridge bytes differ from the reference build (local compiler/toolchain), but pinned source + patch validation passed.' -ForegroundColor Yellow }
    if ($feederHash -eq $ReferenceFeederHash) { Write-Host '  DLSS integration Feeder matches the hardware-tested reference binary.' -ForegroundColor Green }
    else { Write-Host '  NOTE: Feeder bytes differ from the reference build (local compiler/toolchain), but pinned source + CPU tests passed.' -ForegroundColor Yellow }
    if ($shimHash -eq $ReferenceShimHash) { Write-Host '  DLSS integration shim matches the hardware-tested reference binary.' -ForegroundColor Green }
    else { Write-Host '  NOTE: integration shim bytes differ from the reference build (local compiler/toolchain), but pinned source + CPU tests passed.' -ForegroundColor Yellow }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Backup = Join-Path $Game ("_DLSS_FULL_PREINSTALL_BACKUP_" + $stamp)
    New-Item -ItemType Directory -Path $Backup -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Backup '.trex\m3k') -Force | Out-Null
    foreach ($rel in @('d3d9.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll')) {
        Copy-IfExists (Join-Path $Game $rel) (Join-Path $Backup $rel)
    }

    Write-Host ''
    Write-Host 'Installing DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering...' -ForegroundColor Cyan
    Copy-Item -LiteralPath $Bridge -Destination (Join-Path $Game 'd3d9.dll') -Force
    Copy-Item -LiteralPath $Feeder -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force
    New-Item -ItemType Directory -Path (Join-Path $Trex 'm3k') -Force | Out-Null
    Copy-Item -LiteralPath $Shim -Destination (Join-Path $Trex 'm3k\m3k-nvngx.dll') -Force
    Copy-Item -LiteralPath $NrDll.FullName -Destination (Join-Path $Trex 'm3k\nvngx_dlssnr.dll') -Force

    $ini = @(
        '[M3K]',
        '; GTA IV DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering',
        '; Internal checkpoint names: A3-S2 = temporal synchronization; A3-S5 = startup stabilization.',
        '; Mode=0: Neural Rendering OFF (default). Mode=2: Neural Rendering ON before DLSS Super Resolution.',
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

    $controlUrl = 'https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/main/install/DLSS-Full-Control.bat'
    $controlPath = Join-Path $Game 'DLSS-Full-Control.bat'
    Write-Host 'Installing DLSS-Full-Control.bat...' -ForegroundColor Cyan
    Download-File $controlUrl $controlPath

    $receipt = @(
        'GTA IV DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering installation receipt',
        "Installed=$(Get-Date -Format o)",
        "ProjectCheckpoint=$Checkpoint",
        "BBridgeCommit=$BBridgeCommit",
        "SavedDLSSQualityProfile=$profile",
        'NeuralRendering=installed-off-by-default',
        'InternalNRMode=0',
        'NRPasses=1',
        'StartupStabilization=1485x835',
        'StartupStabilizationFrames=180',
        'InternalTemporalCheckpoint=A3-S2',
        'InternalStartupCheckpoint=A3-S5',
        "d3d9.dll=$bridgeHash",
        "dlss5-feed.addon64=$feederHash",
        "m3k-nvngx.dll=$shimHash",
        "nvngx_dlssnr.dll=$NrDllHash",
        "ReferenceA3S2Bridge=$ReferenceBridgeHash",
        "ReferenceA3S5Feeder=$ReferenceFeederHash",
        "ReferenceS27Shim=$ReferenceShimHash",
        "NRPackage=$NrPackageUrl",
        "NRPackageSHA256=$NrPackageHash",
        "Backup=$Backup"
    )
    Write-NoBom (Join-Path $Game 'DLSS_FULL_INSTALLED.txt') $receipt

    Write-Host ''
    Write-Host '====================================================================' -ForegroundColor Green
    Write-Host ' DLSS 4.5 SUPER RESOLUTION + DLSS 5 NEURAL RENDERING INSTALLED' -ForegroundColor Green
    Write-Host '====================================================================' -ForegroundColor Green
    Write-Host "Saved DLSS quality profile: $profile"
    Write-Host 'Neural Rendering runtime: INSTALLED'
    Write-Host 'Neural Rendering: OFF by default'
    Write-Host 'Startup stabilization: 1485x835 -> 180 synchronized frames -> saved DLSS mode'
    Write-Host "Rollback backup: $Backup"
    Write-Host ''
    Write-Host 'Use DLSS-Full-Control.bat to choose DLSS quality, turn Neural Rendering ON/OFF, and launch with startup stabilization.' -ForegroundColor Yellow
    Write-Host 'When NR is ON, one Neural Rendering pass runs before DLSS Super Resolution.'
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