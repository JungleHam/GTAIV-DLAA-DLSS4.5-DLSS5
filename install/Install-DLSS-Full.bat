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
$ReferenceCoreFeederHash = 'C73D8D54271F55F8931F00D62A4CDF605118BEA71D7C6BEE0B61D0CA7C1CCE4B'
$ReferenceShimHash = 'A2E4BEDACE8D99BC60B5D18E958BD7E98F8887FF40EC45A8674B892E2D1FCBBC'
$NrPackageUrl = 'https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0-RTX40/nvngx_dlssnr_310.8.0-RTX40.zip'
$NrPackageHash = '46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F'
$NrDllHash = '4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05'
$DxvkPresenterUrl = 'https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases/download/m3k-dxvk-v3.0.2-a2s1b/d3d9vk_x64.dll'
$DxvkPresenterHash = '511E0C2509E1922DB2EC38940507BA956908FE6DC5FD9B3DB9FEC489DC05F297'
$DxvkPresenterUpstreamCommit = '6b20f622a77b87b2921fe5d2c1774d2f2ba3e9b7'
$PublicControlsCommit = '11ac957138d4c6376d1e6ee6413f32cf9826b422'
$PublicControlsUrl = "https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/$PublicControlsCommit/install/Public-ReShade-Controls-Stage.ps1"
$PublicControlsHash = '0C602D710F62EB6DF15C86B7B5473A7F3E9F2E1CF3270AEA3976EA512F5907A3'
$ControlCommit = 'a6bd0080982398046b20cf39e858f3e016c03492'
$ControlUrl = "https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/$ControlCommit/install/DLSS-Full-Control.bat"
$ControlHash = 'F209610F26970939D5B12EFCC13BEE84BB08348B045B2C4442D3177ED142661D'
$UninstallerCommit = '62af76739c06c0915b64d293d623ec1f591cb0b7'
$UninstallerUrl = "https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/$UninstallerCommit/install/Uninstall-DLSS-Full.bat"
$UninstallerHash = '948ACF211A23EE411B0D823663DE7774C3EE35FFC137CAF0268240CF6D3C14DE'
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
    Write-Host "  Temporary file: $Dest" -ForegroundColor DarkGray
    Write-Host '  This download will be deleted automatically after use, including if installation fails.' -ForegroundColor DarkGray
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -L --fail --retry 3 --connect-timeout 20 --silent --show-error -o $Dest $Url
        if ($LASTEXITCODE -ne 0) { Fail "Download failed: $Url" }
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
    }
    if (-not (Test-Path -LiteralPath $Dest)) { Fail "Downloaded file is missing: $Dest" }
}

function Remove-TemporaryInstallerFiles {
    if (-not (Test-Path -LiteralPath $Temp)) { return }
    Write-Host "Cleaning temporary installer files: $Temp" -ForegroundColor DarkGray
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction Stop
            Write-Host 'Temporary installer files deleted.' -ForegroundColor DarkGray
            return
        } catch {
            if ($attempt -lt 3) { Start-Sleep -Milliseconds 300 }
            else { Write-Host ("WARNING: Could not completely remove temporary installer folder: " + $_.Exception.Message) -ForegroundColor Yellow }
        }
    }
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

function Test-DlaaBaselineSnapshot([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    foreach ($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $rel))) { return $false }
    }
    foreach ($rel in @('.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll')) {
        if (Test-Path -LiteralPath (Join-Path $Path $rel)) { return $false }
    }
    return $true
}

function Save-DlaaBaselineIfPossible {
    $canonical = Join-Path $Game '_DLSS_FULL_DLAA_BASELINE'
    if (Test-DlaaBaselineSnapshot $canonical) { return $canonical }
    if (Test-Path -LiteralPath $canonical) { Remove-Item -LiteralPath $canonical -Recurse -Force }

    $source = $null
    $currentLooksDlaa = $true
    foreach ($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Game $rel))) { $currentLooksDlaa = $false; break }
    }
    foreach ($rel in @('.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll')) {
        if (Test-Path -LiteralPath (Join-Path $Game $rel)) { $currentLooksDlaa = $false }
    }
    if ($currentLooksDlaa) { $source = $Game }
    if (-not $source) {
        $candidates = @(Get-ChildItem -LiteralPath $Game -Directory -Filter '_DLSS_FULL_PREINSTALL_BACKUP_*' -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($candidate in $candidates) {
            if (Test-DlaaBaselineSnapshot $candidate.FullName) { $source = $candidate.FullName; break }
        }
    }
    if (-not $source) {
        Write-Host 'WARNING: Could not establish a trustworthy canonical DLAA rollback snapshot. Existing timestamped backups are left untouched.' -ForegroundColor Yellow
        return $null
    }

    New-Item -ItemType Directory -Path $canonical -Force | Out-Null
    foreach ($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg')) {
        Copy-IfExists (Join-Path $source $rel) (Join-Path $canonical $rel)
    }
    [IO.File]::WriteAllText((Join-Path $canonical 'BASELINE.txt'),
        "DLAA-only rollback baseline`r`nCreated=$(Get-Date -Format o)`r`nSource=$source`r`n",
        (New-Object Text.UTF8Encoding($false)))
    if (-not (Test-DlaaBaselineSnapshot $canonical)) { Fail 'Canonical DLAA rollback baseline validation failed.' }
    Write-Host "Canonical DLAA rollback baseline: $canonical" -ForegroundColor DarkGray
    return $canonical
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

    $profile = '2'
    Write-Host 'Default DLSS Super Resolution quality: Quality.' -ForegroundColor Yellow
    Write-Host 'After installation, change quality and Neural Rendering directly inside the ReShade menu.' -ForegroundColor Yellow

    Remove-TemporaryInstallerFiles
    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    Write-Host "Temporary download/work folder: $Temp" -ForegroundColor DarkGray
    Write-Host 'Everything downloaded, cloned, or built in this folder will be deleted automatically after use, including if installation fails.' -ForegroundColor DarkGray

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

    Write-Host ''
    Write-Host 'Downloading the tested M3K DXVK 3.0.2 render/output presenter...' -ForegroundColor Cyan
    $DxvkPresenterTemp = Join-Path $Temp 'd3d9vk_x64.dll'
    Download-File $DxvkPresenterUrl $DxvkPresenterTemp
    Assert-SHA256 $DxvkPresenterTemp $DxvkPresenterHash

    Write-Host "Downloading/cloning project source into temporary folder: $Project" -ForegroundColor DarkGray
    Write-Host 'This source checkout will be deleted automatically after use, including if installation fails.' -ForegroundColor DarkGray
    Run $Git @('clone','--filter=blob:none',$RepoUrl,$Project) 'Cloning project source'
    Run $Git @('-C',$Project,'checkout',$Checkpoint) 'Checking out the frozen tested project checkpoint'
    $head = (& $Git -C $Project rev-parse HEAD).Trim()
    if ($head -ne $Checkpoint) { Fail "Wrong project revision: $head" }

    Write-Host ''
    Write-Host 'Adding the public ReShade DLSS controls to the frozen rendering core...' -ForegroundColor Cyan
    $publicStage = Join-Path $Project 'tools\m3k-nr\public-reshade-controls-stage.ps1'
    Download-File $PublicControlsUrl $publicStage
    Assert-SHA256 $publicStage $PublicControlsHash

    $buildScript = Join-Path $Project 'tools\m3k-nr\build-a3-s5.ps1'
    $buildText = [IO.File]::ReadAllText($buildScript)
    $buildAnchor = @'
& (Join-Path $toolRoot 'a3-s5-startup-prime-stage.ps1') -GeneratedRoot $generated
'@
    $buildReplacement = @'
& (Join-Path $toolRoot 'a3-s5-startup-prime-stage.ps1') -GeneratedRoot $generated
& (Join-Path $toolRoot 'public-reshade-controls-stage.ps1') -GeneratedRoot $generated -FeederSource (Join-Path $feeder 'src\dlss5-feed.cpp')
'@
    $count = ([regex]::Matches($buildText,[regex]::Escape($buildAnchor))).Count
    if ($count -ne 1) { Fail "Could not attach public ReShade controls stage to frozen build; anchor count=$count" }
    [IO.File]::WriteAllText($buildScript,$buildText.Replace($buildAnchor,$buildReplacement),(New-Object Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host 'Building the tested DLSS integration from pinned sources...' -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript
    if ($LASTEXITCODE -ne 0) { Fail "DLSS integration build failed with exit code $LASTEXITCODE" }

    $Feeder = Join-Path $Project 'tools\m3k-nr\out-m3k-a3-s5\dlss5-feed.addon64'
    $Shim = Join-Path $Project 'tools\m3k-nr\out-m3k-s27\m3k\m3k-nvngx.dll'
    if (-not (Test-Path -LiteralPath $Feeder)) { Fail 'DLSS integration Feeder output is missing.' }
    if (-not (Test-Path -LiteralPath $Shim)) { Fail 'DLSS integration shim output is missing.' }

    Write-Host ''
    Write-Host 'Building the tested temporal-synchronization bridge...' -ForegroundColor Cyan
    Write-Host "Downloading/cloning b-bridge source into temporary folder: $BBridge" -ForegroundColor DarkGray
    Write-Host 'This source checkout and its submodules will be deleted automatically after use, including if installation fails.' -ForegroundColor DarkGray
    Run $Git @('clone','--filter=blob:none','https://github.com/gutbash/b-bridge.git',$BBridge) 'Cloning pinned b-bridge source'
    Run $Git @('-C',$BBridge,'checkout',$BBridgeCommit) 'Checking out pinned b-bridge commit'
    Write-Host "Downloading b-bridge submodules into temporary folder: $BBridge" -ForegroundColor DarkGray
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
    Write-Host "Downloading temporary Python build tools into: $Venv" -ForegroundColor DarkGray
    Write-Host 'pip cache is disabled; the temporary environment will be deleted automatically after use, including if installation fails.' -ForegroundColor DarkGray
    Run $Vpy @('-m','pip','install','--disable-pip-version-check','--no-cache-dir','meson==0.64.1','ninja==1.11.1.1') 'Installing pinned Meson/Ninja build tools'
    $oldPath = $env:PATH
    $env:PATH = (Join-Path $Venv 'Scripts') + ';' + $env:PATH
    Push-Location $BBridge
    try {
        . .\build_common.ps1
        SetupVS -Platform x86
        & meson setup --buildtype release --backend ninja _compDLSSFull32 --debug
        if ($LASTEXITCODE -ne 0) { Fail "x86 bridge client Meson setup failed: $LASTEXITCODE" }
        Copy-Item .\Directory.Build.Props -Destination .\_compDLSSFull32 -Force
        & meson compile -C _compDLSSFull32 d3d9
        if ($LASTEXITCODE -ne 0) { Fail "Temporal-synchronization x86 bridge client build failed: $LASTEXITCODE" }

        # b-bridge requires the 32-bit client and 64-bit server to report the same
        # source version. Build the server from this exact pinned checkout too;
        # keeping the older DLAA release server causes an immediate startup abort.
        SetupVS -Platform x64
        & meson setup --buildtype release --backend ninja _compDLSSFull64 --debug
        if ($LASTEXITCODE -ne 0) { Fail "x64 bridge server Meson setup failed: $LASTEXITCODE" }
        Copy-Item .\Directory.Build.Props -Destination .\_compDLSSFull64 -Force
        & meson compile -C _compDLSSFull64 NvRemixBridge
        if ($LASTEXITCODE -ne 0) { Fail "Matched x64 NvRemixBridge server build failed: $LASTEXITCODE" }
    } finally {
        Pop-Location
        $env:PATH = $oldPath
    }
    $Bridge = Join-Path $BBridge '_compDLSSFull32\src\client\d3d9.dll'
    $BridgeServer = Join-Path $BBridge '_compDLSSFull64\src\server\NvRemixBridge.exe'
    if (-not (Test-Path -LiteralPath $Bridge)) { Fail 'Temporal-synchronization x86 bridge d3d9.dll output is missing.' }
    if (-not (Test-Path -LiteralPath $BridgeServer)) { Fail 'Matched x64 NvRemixBridge.exe output is missing.' }

    $bridgeHash = Hash $Bridge
    $serverHash = Hash $BridgeServer
    $feederHash = Hash $Feeder
    $shimHash = Hash $Shim
    Write-Host ''
    Write-Host 'Build/runtime outputs:' -ForegroundColor Cyan
    Write-Host "  d3d9.dll             $bridgeHash"
    Write-Host "  NvRemixBridge.exe    $serverHash  (same pinned b-bridge commit)"
    Write-Host "  d3d9vk_x64.dll       $DxvkPresenterHash  (M3K render/output presenter)"
    Write-Host "  dlss5-feed.addon64   $feederHash"
    Write-Host "  m3k-nvngx.dll        $shimHash"
    Write-Host "  nvngx_dlssnr.dll     $NrDllHash"
    if ($bridgeHash -eq $ReferenceBridgeHash) { Write-Host '  Temporal-synchronization bridge matches the hardware-tested reference binary.' -ForegroundColor Green }
    else { Write-Host '  NOTE: bridge bytes differ from the reference build (local compiler/toolchain), but pinned source + patch validation passed.' -ForegroundColor Yellow }
    if ($feederHash -eq $ReferenceCoreFeederHash) { Write-Host '  Feeder matches the pre-UI hardware-tested core reference binary.' -ForegroundColor Green }
    else { Write-Host '  NOTE: Feeder differs from the pre-UI hardware reference as expected because the public ReShade controls are compiled into it; frozen rendering core + CPU tests passed.' -ForegroundColor Yellow }
    if ($shimHash -eq $ReferenceShimHash) { Write-Host '  DLSS integration shim matches the hardware-tested reference binary.' -ForegroundColor Green }
    else { Write-Host '  NOTE: integration shim bytes differ from the reference build (local compiler/toolchain), but pinned source + CPU tests passed.' -ForegroundColor Yellow }

    $DlaaBaseline = Save-DlaaBaselineIfPossible

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Backup = Join-Path $Game ("_DLSS_FULL_PREINSTALL_BACKUP_" + $stamp)
    New-Item -ItemType Directory -Path $Backup -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Backup '.trex\m3k') -Force | Out-Null
    foreach ($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll')) {
        Copy-IfExists (Join-Path $Game $rel) (Join-Path $Backup $rel)
    }

    Write-Host ''
    Write-Host 'Installing DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering...' -ForegroundColor Cyan
    Copy-Item -LiteralPath $Bridge -Destination (Join-Path $Game 'd3d9.dll') -Force
    Copy-Item -LiteralPath $BridgeServer -Destination (Join-Path $Trex 'NvRemixBridge.exe') -Force
    if ((Hash (Join-Path $Game 'd3d9.dll')) -ne $bridgeHash) { Fail 'Installed x86 bridge client hash verification failed.' }
    if ((Hash (Join-Path $Trex 'NvRemixBridge.exe')) -ne $serverHash) { Fail 'Installed x64 bridge server hash verification failed.' }
    Copy-Item -LiteralPath $DxvkPresenterTemp -Destination (Join-Path $Trex 'd3d9vk_x64.dll') -Force
    if ((Hash (Join-Path $Trex 'd3d9vk_x64.dll')) -ne $DxvkPresenterHash) { Fail 'Installed M3K DXVK presenter hash verification failed.' }
    Copy-Item -LiteralPath $Feeder -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force
    New-Item -ItemType Directory -Path (Join-Path $Trex 'm3k') -Force | Out-Null
    Copy-Item -LiteralPath $Shim -Destination (Join-Path $Trex 'm3k\m3k-nvngx.dll') -Force
    Copy-Item -LiteralPath $NrDll.FullName -Destination (Join-Path $Trex 'm3k\nvngx_dlssnr.dll') -Force

    $ini = @(
        '[M3K]',
        '; GTA IV DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering',
        '; Change DLSS quality and Neural Rendering from Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS.',
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

    $controlPath = Join-Path $Game 'DLSS-Full-Control.bat'
    $controlTemp = Join-Path $Temp 'DLSS-Full-Control.bat'
    Write-Host 'Installing DLSS-Full-Control.bat (launch / repair / diagnostics)...' -ForegroundColor Cyan
    Download-File $ControlUrl $controlTemp
    Assert-SHA256 $controlTemp $ControlHash
    Copy-Item -LiteralPath $controlTemp -Destination $controlPath -Force

    $uninstallerPath = Join-Path $Game 'Uninstall-DLSS-Full.bat'
    $uninstallerTemp = Join-Path $Temp 'Uninstall-DLSS-Full.bat'
    Write-Host 'Installing Uninstall-DLSS-Full.bat (restore DLAA-only baseline)...' -ForegroundColor Cyan
    Download-File $UninstallerUrl $uninstallerTemp
    Assert-SHA256 $uninstallerTemp $UninstallerHash
    Copy-Item -LiteralPath $uninstallerTemp -Destination $uninstallerPath -Force

    $receipt = @(
        'GTA IV DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering installation receipt',
        "Installed=$(Get-Date -Format o)",
        "ProjectCheckpoint=$Checkpoint",
        "BBridgeCommit=$BBridgeCommit",
        'DefaultDLSSQuality=Quality',
        'NeuralRendering=installed-off-by-default',
        'NRPasses=1',
        'SettingsSurface=ReShade Home > Add-ons > DLSS 5 Feed > GTA IV DLSS',
        'StartupStabilization=1485x835',
        'StartupStabilizationFrames=180',
        "PublicControlsCommit=$PublicControlsCommit",
        "PublicControlsSHA256=$PublicControlsHash",
        "UninstallerCommit=$UninstallerCommit",
        "UninstallerSHA256=$UninstallerHash",
        "DlaaBaseline=$DlaaBaseline",
        "d3d9.dll=$bridgeHash",
        "NvRemixBridge.exe=$serverHash",
        "d3d9vk_x64.dll=$DxvkPresenterHash",
        "DxvkPresenterUpstreamCommit=$DxvkPresenterUpstreamCommit",
        "DxvkPresenterURL=$DxvkPresenterUrl",
        "dlss5-feed.addon64=$feederHash",
        "m3k-nvngx.dll=$shimHash",
        "nvngx_dlssnr.dll=$NrDllHash",
        "ReferenceA3S2Bridge=$ReferenceBridgeHash",
        "ReferencePreUiA3S5Feeder=$ReferenceCoreFeederHash",
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
    Write-Host 'Default DLSS quality: Quality'
    Write-Host 'Neural Rendering runtime: INSTALLED'
    Write-Host 'Neural Rendering: OFF by default'
    Write-Host 'Neural Rendering passes: 1 (tested public default)'
    Write-Host 'Startup stabilization: 1485x835 -> 180 synchronized frames -> saved DLSS mode'
    Write-Host "Rollback backup: $Backup"
    Write-Host ''
    Write-Host 'Normal settings are now inside ReShade:' -ForegroundColor Yellow
    Write-Host '  Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS'
    Write-Host 'Use DLSS-Full-Control.bat only for launch, repair, status, and logs.' -ForegroundColor Yellow
    Write-Host 'Use Uninstall-DLSS-Full.bat to roll back to the preserved DLAA + ReShade input-patch baseline.' -ForegroundColor Yellow
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
    Remove-TemporaryInstallerFiles
    if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
}

exit 0