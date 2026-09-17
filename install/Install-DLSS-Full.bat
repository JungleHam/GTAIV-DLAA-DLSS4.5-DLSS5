@echo off
setlocal
set "GTAIV_SETUP_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:GTAIV_SETUP_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Self = $env:GTAIV_SETUP_SELF
$Repo = 'JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5'
$RuntimeTag = 'runtime-prebuilt-v1'
$RuntimeUrl = "https://github.com/$Repo/releases/download/$RuntimeTag/GTAIV-DLSS-Full-Runtime.zip"
$RuntimeZipHash = '1E14F1508A1AC1FAC8EAB2DD0E3D8969C99275363B43C47406D0A86D5BE36987'
$RuntimeHashes = @{
    'd3d9.dll'='ECA7C9CF9CD1C4835CEA7FD57AD168A35E157F081C0EADBA51AF35F501026F28';
    'NvRemixBridge.exe'='8A89A3DBBC02D56BA98254941B14E52D88EFEF3F95E491C9C6AF5ADC65FECFFA';
    'd3d9vk_x64.dll'='511E0C2509E1922DB2EC38940507BA956908FE6DC5FD9B3DB9FEC489DC05F297';
    'dlss5-feed.addon64'='95259612C7AA82DFC913E6AC4405A27B41C29F0DE4975592E972A9A1435879B2';
    'm3k\m3k-nvngx.dll'='69D63D238780F93F8ABC3D59C97C9E577A7845C557C1DC7A8F28FF3A84AAE51A'
}
$Nr50Url = 'https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0/nvngx_dlssnr_310.8.0.zip'
$Nr50PackageHash = '388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC'
$Nr50DllHash = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$Nr40Url = 'https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0-RTX40/nvngx_dlssnr_310.8.0-RTX40.zip'
$Nr40PackageHash = '46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F'
$Nr40DllHash = '4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05'
$ControlUrl = 'https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/a6bd0080982398046b20cf39e858f3e016c03492/install/DLSS-Full-Control.bat'
$ControlHash = 'F209610F26970939D5B12EFCC13BEE84BB08348B045B2C4442D3177ED142661D'
$UninstallerUrl = 'https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/e4c600a96e1b3682d7004dbd04dffc1abace7b90/install/Uninstall-DLSS-Full.bat'
$UninstallerHash = '0AF505444E966FB61AB9C83EB7F4D8874A436E4302AB935CAA2DBA0039656733'
$Temp = Join-Path $env:TEMP ("GTAIV_DLSS_RELEASE_" + $PID)
$Backup = $null
$InstallStarted = $false

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Fail([string]$m) { throw $m }
function Download([string]$u,[string]$p) {
    Write-Host "Downloading: $u" -ForegroundColor DarkGray
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) { & curl.exe -L --fail --retry 3 --connect-timeout 20 --silent --show-error -o $p $u; if ($LASTEXITCODE -ne 0) { Fail "Download failed: $u" } }
    else { Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p }
    if (-not (Test-Path -LiteralPath $p)) { Fail "Downloaded file is missing: $p" }
}
function Hash([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return '<missing>' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant()
}
function Assert-SHA256([string]$p,[string]$expected) {
    $actual = Hash $p
    if ($actual -ne $expected.ToUpperInvariant()) { Fail "SHA256 mismatch for $p`nExpected: $expected`nActual:   $actual" }
}
function Resolve-GameFolder {
    Write-Host ''
    Write-Host 'Enter the GTA IV folder that contains GTAIV.exe.' -ForegroundColor Cyan
    $raw = (Read-Host 'GTA IV folder').Trim().Trim('"')
    if (-not $raw) { Fail 'No folder entered.' }
    if ((Test-Path -LiteralPath $raw -PathType Leaf) -and ([IO.Path]::GetFileName($raw) -ieq 'GTAIV.exe')) { $raw = Split-Path -Parent $raw }
    if (Test-Path -LiteralPath (Join-Path $raw 'GTAIV.exe')) { return (Resolve-Path -LiteralPath $raw).Path }
    $nested = Join-Path $raw 'GTAIV'
    if (Test-Path -LiteralPath (Join-Path $nested 'GTAIV.exe')) { return (Resolve-Path -LiteralPath $nested).Path }
    Fail 'GTAIV.exe was not found in that folder.'
}
function Copy-IfExists([string]$src,[string]$dst) {
    if (-not (Test-Path -LiteralPath $src)) { return }
    $parent = Split-Path -Parent $dst
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
}
function Write-NoBom([string]$Path,[string[]]$Lines) {
    [IO.File]::WriteAllLines($Path,$Lines,[Text.UTF8Encoding]::new($false))
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
    [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}
function Save-DlaaBaseline([string]$Game,[string]$Trex) {
    $canonical = Join-Path $Game '_DLSS_FULL_DLAA_BASELINE'
    $required = @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg')
    $valid = Test-Path -LiteralPath $canonical -PathType Container
    if ($valid) { foreach ($rel in $required) { if (-not (Test-Path -LiteralPath (Join-Path $canonical $rel))) { $valid=$false; break } } }
    if ($valid) { return $canonical }
    if (Test-Path -LiteralPath $canonical) { Remove-Item -LiteralPath $canonical -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $canonical '.trex') -Force | Out-Null
    foreach ($rel in $required) {
        $src = Join-Path $Game $rel
        if (-not (Test-Path -LiteralPath $src)) { Fail "Cannot preserve DLAA rollback baseline; missing $rel" }
        Copy-IfExists $src (Join-Path $canonical $rel)
    }
    Write-NoBom (Join-Path $canonical 'BASELINE.txt') @('DLAA-only rollback baseline',"Created=$(Get-Date -Format o)")
    return $canonical
}
function Snapshot-Current([string]$Game,[string]$Dest) {
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    $files = @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat','DLSS_FULL_INSTALLED.txt')
    foreach ($rel in $files) { Copy-IfExists (Join-Path $Game $rel) (Join-Path $Dest $rel) }
}
function Restore-Snapshot([string]$Game,[string]$Dest) {
    $files = @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat','DLSS_FULL_INSTALLED.txt')
    foreach ($rel in $files) {
        $dst = Join-Path $Game $rel
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue }
        Copy-IfExists (Join-Path $Dest $rel) $dst
    }
}

if (-not (Is-Admin)) {
    Write-Host 'Administrator permission is required. Approve the Windows prompt.' -ForegroundColor Yellow
    $p = Start-Process -FilePath $Self -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}

try {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' GTA IV - DLSS Full + Neural Rendering' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    $Game = Resolve-GameFolder
    $Trex = Join-Path $Game '.trex'
    foreach ($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\nvngx_dlss.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Game $rel))) { Fail "DLAA/ReShade step is incomplete; missing $rel. Run Install-DLAA.bat first." }
    }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV first.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe first.' }

    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
    $gpuName = if ($gpu) { [string]$gpu.Name } else { 'NVIDIA GPU not detected by Windows' }
    if ($gpuName -match 'RTX\s*50') {
        $flavor='RTX50'; $nrLabel='Original NVIDIA-signed DLSS NR 310.8 (RTX 50)'; $nrUrl=$Nr50Url; $nrPkg=$Nr50PackageHash; $nrDll=$Nr50DllHash
    } elseif ($gpuName -match 'RTX\s*40') {
        $flavor='RTX40'; $nrLabel='RTX 40 compatibility DLSS NR 310.8 (project-tested)'; $nrUrl=$Nr40Url; $nrPkg=$Nr40PackageHash; $nrDll=$Nr40DllHash
    } else {
        Write-Host ''
        Write-Host "Detected GPU: $gpuName" -ForegroundColor Yellow
        Write-Host '1 - RTX 50: original NVIDIA-signed runtime'
        Write-Host '2 - RTX 40: project-tested compatibility runtime'
        $pick = Read-Host 'Choose 1 or 2'
        if ($pick -eq '1') { $flavor='RTX50'; $nrLabel='Original NVIDIA-signed DLSS NR 310.8 (RTX 50)'; $nrUrl=$Nr50Url; $nrPkg=$Nr50PackageHash; $nrDll=$Nr50DllHash }
        elseif ($pick -eq '2') { $flavor='RTX40'; $nrLabel='RTX 40 compatibility DLSS NR 310.8 (project-tested)'; $nrUrl=$Nr40Url; $nrPkg=$Nr40PackageHash; $nrDll=$Nr40DllHash }
        else { Fail 'No supported Neural Rendering runtime was selected.' }
    }

    Write-Host ''
    Write-Host "Game: $Game"
    Write-Host "GPU:  $gpuName"
    Write-Host "NR:   $nrLabel"
    Write-Host 'DLSS default: Quality | Neural Rendering default: OFF'
    Write-Host 'Prebuilt runtime: verified GitHub Release; no local compiler/build tools required.' -ForegroundColor Green
    $ok = Read-Host 'Continue? [Y/n]'
    if ($ok -and $ok -notmatch '^(y|yes)$') { exit 0 }

    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    $runtimeZip = Join-Path $Temp 'GTAIV-DLSS-Full-Runtime.zip'
    $runtimeDir = Join-Path $Temp 'runtime'
    $nrZip = Join-Path $Temp 'nr.zip'
    $nrDir = Join-Path $Temp 'nr'

    Write-Host ''
    Write-Host '[1/3] Downloading verified prebuilt DLSS runtime...' -ForegroundColor Cyan
    Download $RuntimeUrl $runtimeZip
    Assert-SHA256 $runtimeZip $RuntimeZipHash
    Expand-Archive -LiteralPath $runtimeZip -DestinationPath $runtimeDir -Force
    foreach ($rel in $RuntimeHashes.Keys) {
        $p = Join-Path $runtimeDir $rel
        if (-not (Test-Path -LiteralPath $p)) { Fail "Runtime archive is missing $rel" }
        Assert-SHA256 $p $RuntimeHashes[$rel]
    }

    Write-Host '[2/3] Downloading verified Neural Rendering runtime...' -ForegroundColor Cyan
    Download $nrUrl $nrZip
    Assert-SHA256 $nrZip $nrPkg
    Expand-Archive -LiteralPath $nrZip -DestinationPath $nrDir -Force
    $nrFile = Get-ChildItem -LiteralPath $nrDir -Recurse -File -Filter 'nvngx_dlssnr.dll' | Select-Object -First 1
    if (-not $nrFile) { Fail 'Neural Rendering package did not contain nvngx_dlssnr.dll.' }
    Assert-SHA256 $nrFile.FullName $nrDll
    if ($flavor -eq 'RTX50') {
        $sig = Get-AuthenticodeSignature -LiteralPath $nrFile.FullName
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA') { Fail 'RTX 50 Neural Rendering runtime did not pass NVIDIA Authenticode verification.' }
    }

    $baseline = Save-DlaaBaseline $Game $Trex
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Backup = Join-Path $Game ("_DLSS_FULL_PREINSTALL_BACKUP_" + $stamp)
    Snapshot-Current $Game $Backup

    Write-Host '[3/3] Installing DLSS Full runtime...' -ForegroundColor Cyan
    $InstallStarted = $true
    Copy-Item -LiteralPath (Join-Path $runtimeDir 'd3d9.dll') -Destination (Join-Path $Game 'd3d9.dll') -Force
    Copy-Item -LiteralPath (Join-Path $runtimeDir 'NvRemixBridge.exe') -Destination (Join-Path $Trex 'NvRemixBridge.exe') -Force
    Copy-Item -LiteralPath (Join-Path $runtimeDir 'd3d9vk_x64.dll') -Destination (Join-Path $Trex 'd3d9vk_x64.dll') -Force
    Copy-Item -LiteralPath (Join-Path $runtimeDir 'dlss5-feed.addon64') -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force
    New-Item -ItemType Directory -Path (Join-Path $Trex 'm3k') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $runtimeDir 'm3k\m3k-nvngx.dll') -Destination (Join-Path $Trex 'm3k\m3k-nvngx.dll') -Force
    Copy-Item -LiteralPath $nrFile.FullName -Destination (Join-Path $Trex 'm3k\nvngx_dlssnr.dll') -Force

    foreach ($pair in @(
        @((Join-Path $Game 'd3d9.dll'),$RuntimeHashes['d3d9.dll']),
        @((Join-Path $Trex 'NvRemixBridge.exe'),$RuntimeHashes['NvRemixBridge.exe']),
        @((Join-Path $Trex 'd3d9vk_x64.dll'),$RuntimeHashes['d3d9vk_x64.dll']),
        @((Join-Path $Trex 'dlss5-feed.addon64'),$RuntimeHashes['dlss5-feed.addon64']),
        @((Join-Path $Trex 'm3k\m3k-nvngx.dll'),$RuntimeHashes['m3k\m3k-nvngx.dll']),
        @((Join-Path $Trex 'm3k\nvngx_dlssnr.dll'),$nrDll)
    )) { Assert-SHA256 $pair[0] $pair[1] }

    Write-NoBom (Join-Path $Trex 'm3k-nr.ini') @(
        '[M3K]',
        '; GTA IV DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering',
        '; Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS',
        'MasterEnabled=1',
        'LastSRProfile=2',
        'LastNRMode=0',
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
        'SRProfile=2',
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
    $feedCfg = Join-Path $Trex 'dlss5-feed.cfg'
    Set-KeyEquals $feedCfg 'enabled' '1'
    Set-KeyEquals $feedCfg 'mode' '2'
    Set-KeyEquals $feedCfg 'work_resolution' '100'

    $control = Join-Path $Temp 'DLSS-Full-Control.bat'
    Download $ControlUrl $control; Assert-SHA256 $control $ControlHash
    Copy-Item -LiteralPath $control -Destination (Join-Path $Game 'DLSS-Full-Control.bat') -Force
    $uninstaller = Join-Path $Temp 'Uninstall-DLSS-Full.bat'
    Download $UninstallerUrl $uninstaller; Assert-SHA256 $uninstaller $UninstallerHash
    Copy-Item -LiteralPath $uninstaller -Destination (Join-Path $Game 'Uninstall-DLSS-Full.bat') -Force

    Write-NoBom (Join-Path $Game 'DLSS_FULL_INSTALLED.txt') @(
        'GTA IV DLSS Full prebuilt installation receipt',
        "Installed=$(Get-Date -Format o)",
        "RuntimeTag=$RuntimeTag",
        "RuntimeZipSHA256=$RuntimeZipHash",
        'DefaultDLSSQuality=Quality',
        'MasterProcessing=ON-by-default; OFF-session-only; staged-native-bypass-v2',
        'NeuralRendering=installed-off-by-default',
        'NRPasses=1',
        'StartupStabilization=1485x835',
        'StartupStabilizationFrames=180',
        "NRRuntimeFlavor=$flavor",
        "NRRuntimeLabel=$nrLabel",
        "DlaaBaseline=$baseline",
        "Backup=$Backup",
        "d3d9.dll=$($RuntimeHashes['d3d9.dll'])",
        "NvRemixBridge.exe=$($RuntimeHashes['NvRemixBridge.exe'])",
        "d3d9vk_x64.dll=$($RuntimeHashes['d3d9vk_x64.dll'])",
        "dlss5-feed.addon64=$($RuntimeHashes['dlss5-feed.addon64'])",
        "m3k-nvngx.dll=$($RuntimeHashes['m3k\m3k-nvngx.dll'])",
        "nvngx_dlssnr.dll=$nrDll"
    )

    Write-Host ''
    Write-Host 'DONE - DLSS Full + Neural Rendering installed.' -ForegroundColor Green
    Write-Host 'In game: Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS' -ForegroundColor Cyan
    Write-Host 'Keep GTA IV itself set to your display native resolution; DLSS changes the internal render size.' -ForegroundColor White
    Start-Sleep -Seconds 5
    exit 0
}
catch {
    Write-Host ''
    Write-Host ('INSTALL FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    if ($InstallStarted -and $Backup -and (Test-Path -LiteralPath $Backup)) {
        Write-Host 'Restoring the pre-install runtime...' -ForegroundColor Yellow
        try { Restore-Snapshot $Game $Backup; Write-Host 'Rollback completed.' -ForegroundColor Green }
        catch { Write-Host ('Rollback error: ' + $_.Exception.Message) -ForegroundColor Red }
    }
    Read-Host 'Press Enter to close'
    exit 1
}
finally {
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
