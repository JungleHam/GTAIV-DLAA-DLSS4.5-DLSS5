@rem GTAIV-DLAA-DLSS5 project installer. See repository README before use.
@echo off
setlocal
set "DLAA_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:DLAA_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Self = $env:DLAA_SELF
$Game = Split-Path -Parent $Self
$Trex = Join-Path $Game '.trex'
$Temp = Join-Path $env:TEMP ("GTAIV_DLAA_AIO_" + $PID)
$ReshadeSetup = Join-Path $Temp 'ReShade_Setup_6.8.0_Addon.exe'
$ReShadeInstalled = $false
$TranscriptStarted = $false

function Fail([string]$Message) { throw $Message }

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Download-File([string]$Url, [string]$Dest) {
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

function Assert-SHA256([string]$Path, [string]$Expected) {
    $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected.ToLowerInvariant()) {
        Fail "SHA256 mismatch for $Path`nExpected: $Expected`nActual:   $Actual"
    }
}

function Write-NoBom([string]$Path, [string[]]$Lines) {
    [IO.File]::WriteAllLines($Path, $Lines, (New-Object Text.UTF8Encoding($false)))
}

function Set-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$Value) {
    if (Test-Path -LiteralPath $Path) { $arr = @(Get-Content -LiteralPath $Path) } else { $arr = @() }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($x in $arr) { [void]$lines.Add([string]$x) }
    $sec = '[' + $Section + ']'
    $start = -1
    for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ieq $sec) { $start = $i; break } }
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count-1] -ne '') { [void]$lines.Add('') }
        [void]$lines.Add($sec); [void]$lines.Add("$Key=$Value")
    } else {
        $end = $lines.Count
        for ($i=$start+1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[.+\]\s*$') { $end = $i; break } }
        $found = $false
        for ($i=$start+1; $i -lt $end; $i++) {
            if ($lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) { $lines[$i] = "$Key=$Value"; $found = $true; break }
        }
        if (-not $found) { $lines.Insert($start+1, "$Key=$Value") }
    }
    Write-NoBom $Path $lines.ToArray()
}

function Set-KeyEquals([string]$Path, [string]$Key, [string]$Value) {
    $text = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
    $pat = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*.*$'
    $line = "$Key = $Value"
    if ($text -match $pat) { $text = [regex]::Replace($text, $pat, $line) }
    else { if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`r`n" }; $text += $line + "`r`n" }
    [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Copy-IfExists([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Source) {
        $parent = Split-Path -Parent $Destination
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
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

if (-not (Is-Admin)) {
    Write-Host "Administrator permission is required once for the ReShade Vulkan layer." -ForegroundColor Yellow
    $p = Start-Process -FilePath $Self -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}

Set-Location -LiteralPath $Game
$Log = Join-Path $Game 'DLAA_AIO_install.log'
try {
    Start-Transcript -LiteralPath $Log -Force | Out-Null
    $TranscriptStarted = $true

    Write-Host ''
    Write-Host '========================================================' -ForegroundColor Green
    Write-Host ' GTA IV + FusionFix -> b-bridge -> ReShade -> DLAA AIO' -ForegroundColor Green
    Write-Host '========================================================' -ForegroundColor Green
    Write-Host "Game folder: $Game"
    Write-Host ''

    if (-not (Test-Path -LiteralPath (Join-Path $Game 'GTAIV.exe'))) { Fail 'Put this BAT in the GTAIV folder containing GTAIV.exe.' }
    if (-not (Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))) { Fail 'dinput8.dll is missing. Start from a clean FusionFix installation.' }

    $ffCfg = Join-Path $Game 'plugins\GTAIV.EFLC.FusionFix.cfg'
    if (-not (Test-Path -LiteralPath $ffCfg)) {
        $ffCfgObj = Get-ChildItem -LiteralPath (Join-Path $Game 'plugins') -Filter '*FusionFix*.cfg' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $ffCfgObj) { Fail 'FusionFix CFG not found. Install FusionFix first.' }
        $ffCfg = $ffCfgObj.FullName
    }

    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before running the installer.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before running the installer.' }
    if (Test-Path -LiteralPath $Trex) { Fail '.trex already exists. This AIO is for a CLEAN FusionFix baseline. Restore/clean the previous bridge attempt first.' }
    if (Test-Path -LiteralPath (Join-Path $Game 'd3d9Hooked.dll')) { Fail 'd3d9Hooked.dll already exists. This does not look like a clean FusionFix baseline.' }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Backup = Join-Path $Game ("_DLAA_PREINSTALL_BACKUP_" + $stamp)
    New-Item -ItemType Directory -Path $Backup -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Backup 'plugins') -Force | Out-Null
    foreach ($name in @('d3d9.dll','vulkan.dll','dxvk.conf','commandline.txt')) { Copy-IfExists (Join-Path $Game $name) (Join-Path $Backup $name) }
    Copy-IfExists $ffCfg (Join-Path $Backup ('plugins\' + [IO.Path]::GetFileName($ffCfg)))
    $ffIni = Join-Path (Split-Path -Parent $ffCfg) 'GTAIV.EFLC.FusionFix.ini'
    Copy-IfExists $ffIni (Join-Path $Backup 'plugins\GTAIV.EFLC.FusionFix.ini')
    Write-Host "Backup: $Backup" -ForegroundColor DarkGray

    Remove-TemporaryInstallerFiles
    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    Write-Host "Temporary download/work folder: $Temp" -ForegroundColor DarkGray
    Write-Host 'Everything downloaded into this folder will be deleted automatically after use, including if installation fails.' -ForegroundColor DarkGray
    $bZip = Join-Path $Temp 'bbridge.zip'; $fZip = Join-Path $Temp 'feeder.zip'; $lZip = Join-Path $Temp 'lumenite.zip'; $dZip = Join-Path $Temp 'dlss.zip'

    Download-File 'https://github.com/gutbash/b-bridge/releases/download/v0.1.0/b-bridge-0.1.0.zip' $bZip
    Assert-SHA256 $bZip 'd5691ad68cca6e731bbe12b34b14b6a8288e2e7e319e8ef0e13e0f3a59c31c55'
    Download-File 'https://github.com/jlrouzies-fr/DLSS5-Feeder/releases/download/v0.15.1/DLSS5-Feeder-0.15.1.zip' $fZip
    Assert-SHA256 $fZip '2e44e81e691e75e532b9b7babc278a12615cb7f0fd9ef854da50e6ef17b272f4'
    Download-File 'https://codeload.github.com/umar-afzaal/LumeniteFX/zip/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9' $lZip
    Download-File 'https://github.com/RankFTW/rhi-repo/releases/download/dlss-310.9.1/nvngx_dlss_310.9.1.zip' $dZip
    Assert-SHA256 $dZip 'aaba83b288bd145c3808e8d7a0ba03cc8c8676d18ad984b1bfa6563046a3ba37'

    try { Download-File 'https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe' $ReshadeSetup }
    catch { Write-Host 'Primary ReShade URL failed; trying official alternate...' -ForegroundColor Yellow; Download-File 'https://www.reshade.me/releases/ReShade-6.8.0-Addon-setup.exe' $ReshadeSetup }
    if ((Get-Item -LiteralPath $ReshadeSetup).Length -lt 1MB) { Fail 'ReShade setup download is unexpectedly small.' }

    Write-Host 'Extracting packages...' -ForegroundColor Cyan
    Expand-Archive -LiteralPath $bZip -DestinationPath (Join-Path $Temp 'bbridge') -Force
    Expand-Archive -LiteralPath $fZip -DestinationPath (Join-Path $Temp 'feeder') -Force
    Expand-Archive -LiteralPath $lZip -DestinationPath (Join-Path $Temp 'lumenite') -Force
    Expand-Archive -LiteralPath $dZip -DestinationPath (Join-Path $Temp 'dlss') -Force

    Write-Host 'Configuring FusionFix...' -ForegroundColor Cyan
    Set-IniValue $ffCfg 'MAIN' 'GraphicsAPI' '0'; Set-IniValue $ffCfg 'MAIN' 'Windowed' '1'; Set-IniValue $ffCfg 'MAIN' 'BorderlessWindowed' '1'; Set-IniValue $ffCfg 'FRAMELIMIT' 'FpsLimitPreset' '0'; Set-IniValue $ffCfg 'MISC' 'Antialiasing' '5'
    $cmdPath = Join-Path $Game 'commandline.txt'
    $cmd = if (Test-Path -LiteralPath $cmdPath) { [IO.File]::ReadAllText($cmdPath) } else { '' }
    if ($cmd -notmatch '(?i)(^|\s)-windowed(\s|$)') { if ($cmd.Trim().Length -gt 0) { $cmd = $cmd.TrimEnd() + "`r`n" }; $cmd += "-windowed`r`n"; [IO.File]::WriteAllText($cmdPath, $cmd, (New-Object Text.UTF8Encoding($false))) }

    Write-Host 'Installing b-bridge 0.1.0...' -ForegroundColor Cyan
    $bridgeClient = Get-ChildItem -LiteralPath (Join-Path $Temp 'bbridge') -Filter 'd3d9.dll' -File -Recurse | Where-Object { Test-Path -LiteralPath (Join-Path $_.Directory.FullName '.trex\NvRemixBridge.exe') } | Select-Object -First 1
    if (-not $bridgeClient) { Fail 'Could not locate the b-bridge GTAIV payload.' }
    $bSrc = $bridgeClient.Directory.FullName
    $rootD3D9 = Join-Path $Game 'd3d9.dll'
    if (Test-Path -LiteralPath $rootD3D9) { Move-Item -LiteralPath $rootD3D9 -Destination (Join-Path $Game 'd3d9Hooked.dll') -Force }
    Copy-Item -LiteralPath (Join-Path $bSrc 'd3d9.dll') -Destination $rootD3D9 -Force
    if (Test-Path -LiteralPath (Join-Path $bSrc 'dxvk.conf')) { Copy-Item -LiteralPath (Join-Path $bSrc 'dxvk.conf') -Destination (Join-Path $Game 'dxvk.conf') -Force }
    Copy-Item -LiteralPath (Join-Path $bSrc '.trex') -Destination $Game -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $Trex 'NvRemixBridge.exe'))) { Fail 'b-bridge server was not installed.' }
    Set-KeyEquals (Join-Path $Trex 'bridge.conf') 'clientFrameCap' '0'

    $dxvk = Join-Path $Game 'dxvk.conf'
    if (Test-Path -LiteralPath $dxvk) {
        $dx = [IO.File]::ReadAllText($dxvk)
        $dx = [regex]::Replace($dx, '(?m)^\s*dxvk\.allowFse\s*=.*$', 'dxvk.allowFse = false')
        $dx = [regex]::Replace($dx, '(?m)^\s*(dxvk\.maxFrameRate\s*=.*)$', '# $1')
        $dx = [regex]::Replace($dx, '(?m)^\s*(dxvk\.latencySleep\s*=.*)$', '# $1')
        [IO.File]::WriteAllText($dxvk, $dx, (New-Object Text.UTF8Encoding($false)))
    }

    Write-Host 'Installing ReShade 6.8.0 Full Add-On Support (Vulkan, headless)...' -ForegroundColor Cyan
    $rsTarget = Join-Path $Trex 'NvRemixBridge.exe'
    $rs = Start-Process -FilePath $ReshadeSetup -ArgumentList @("`"$rsTarget`"",'--api','vulkan','--headless') -Wait -PassThru
    if ($rs.ExitCode -ne 0) { Fail "ReShade setup failed with exit code $($rs.ExitCode)." }
    $ReShadeInstalled = $true
    $rsIni = Join-Path $Trex 'ReShade.ini'
    if (-not (Test-Path -LiteralPath $rsIni)) { Fail 'ReShade.ini was not created in .trex.' }

    Write-Host 'Installing DLSS5-Feeder 0.15.1 in DLAA-only mode...' -ForegroundColor Cyan
    $shaderDir = Join-Path $Trex 'reshade-shaders\Shaders'; $texDir = Join-Path $Trex 'reshade-shaders\Textures'
    New-Item -ItemType Directory -Path $shaderDir -Force | Out-Null; New-Item -ItemType Directory -Path $texDir -Force | Out-Null
    $addon = Get-ChildItem -LiteralPath (Join-Path $Temp 'feeder') -Filter 'dlss5-feed.addon64' -File -Recurse | Select-Object -First 1
    $feedFx = Get-ChildItem -LiteralPath (Join-Path $Temp 'feeder') -Filter 'DLSS5_Feed.fx' -File -Recurse | Select-Object -First 1
    if (-not $addon -or -not $feedFx) { Fail 'Feeder archive is missing dlss5-feed.addon64 or DLSS5_Feed.fx.' }
    Copy-Item -LiteralPath $addon.FullName -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force; Copy-Item -LiteralPath $feedFx.FullName -Destination (Join-Path $shaderDir 'DLSS5_Feed.fx') -Force
    $lumKernel = Get-ChildItem -LiteralPath (Join-Path $Temp 'lumenite') -Filter 'lumenite_Kernel.fx' -File -Recurse | Select-Object -First 1
    if (-not $lumKernel) { Fail 'Lumenite Kernel was not found.' }
    Copy-Item -Path (Join-Path $lumKernel.Directory.FullName '*') -Destination $shaderDir -Recurse -Force
    $lumBlue = Get-ChildItem -LiteralPath (Join-Path $Temp 'lumenite') -Filter 'lumenite_bluenoise256.png' -File -Recurse | Select-Object -First 1
    if ($lumBlue) { Copy-Item -LiteralPath $lumBlue.FullName -Destination (Join-Path $texDir 'lumenite_bluenoise256.png') -Force }
    $dlssDll = Get-ChildItem -LiteralPath (Join-Path $Temp 'dlss') -Filter 'nvngx_dlss.dll' -File -Recurse | Select-Object -First 1
    if (-not $dlssDll) { Fail 'nvngx_dlss.dll was not found in the DLSS 310.9.1 package.' }
    Copy-Item -LiteralPath $dlssDll.FullName -Destination (Join-Path $Trex 'nvngx_dlss.dll') -Force

    $hdrBase = 'https://raw.githubusercontent.com/crosire/reshade-shaders/6db142b4b1a05c764222e5b0bd9a644b7ccfe1dc/Shaders'
    $headersTemp = Join-Path $Temp 'reshade-headers'
    New-Item -ItemType Directory -Path $headersTemp -Force | Out-Null
    $hdrReShade = Join-Path $headersTemp 'ReShade.fxh'
    $hdrReShadeUI = Join-Path $headersTemp 'ReShadeUI.fxh'
    $hdrDrawText = Join-Path $headersTemp 'DrawText.fxh'
    Download-File "$hdrBase/ReShade.fxh" $hdrReShade
    Download-File "$hdrBase/ReShadeUI.fxh" $hdrReShadeUI
    Download-File "$hdrBase/DrawText.fxh" $hdrDrawText
    Copy-Item -LiteralPath $hdrReShade -Destination (Join-Path $shaderDir 'ReShade.fxh') -Force
    Copy-Item -LiteralPath $hdrReShadeUI -Destination (Join-Path $shaderDir 'ReShadeUI.fxh') -Force
    Copy-Item -LiteralPath $hdrDrawText -Destination (Join-Path $shaderDir 'DrawText.fxh') -Force
    Set-IniValue $rsIni 'GENERAL' 'EffectSearchPaths' '.\reshade-shaders\Shaders'; Set-IniValue $rsIni 'GENERAL' 'TextureSearchPaths' '.\reshade-shaders\Textures'; Set-IniValue $rsIni 'GENERAL' 'PresetPath' '.\ReShadePreset.ini'; Set-IniValue $rsIni 'ADDON' 'AddonPath' '.\'
    Write-NoBom (Join-Path $Trex 'ReShadePreset.ini') @('Techniques=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx','TechniqueSorting=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx,DLSS5_Feed_Debug@DLSS5_Feed.fx','','[DLSS5_Feed.fx]','PreprocessorDefinitions=DLSS5_MV_PROVIDER=3')
    Write-NoBom (Join-Path $Trex 'dlss5-feed.cfg') @('enabled=1','mode=2','work_resolution=100')

    foreach ($n in @('nvngx_dlssnr.dll','renodx-dlss5.addon64','deep-fried-chicken.addon64','deep-fried-chicken-nvngx.dll','OptiScaler.dll','OptiScaler.ini')) { $p = Join-Path $Trex $n; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
    foreach ($p in @((Join-Path $Game 'd3d9.dll'),(Join-Path $Game 'dinput8.dll'),(Join-Path $Trex 'NvRemixBridge.exe'),(Join-Path $Trex 'd3d9vk_x64.dll'),(Join-Path $Trex 'ReShade.ini'),(Join-Path $Trex 'dlss5-feed.addon64'),(Join-Path $Trex 'nvngx_dlss.dll'),(Join-Path $shaderDir 'DLSS5_Feed.fx'),(Join-Path $shaderDir 'lumenite_Kernel.fx'),(Join-Path $Trex 'ReShadePreset.ini'),(Join-Path $Trex 'dlss5-feed.cfg'))) { if (-not (Test-Path -LiteralPath $p)) { Fail "Final validation failed: missing $p" } }

    $manifest = @"
GTA IV DLAA all-in-one installation
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Confirmed stack:
FusionFix: DirectX 9, windowed + borderless, FusionFix AA OFF
b-bridge: 0.1.0
DXVK server: b-bridge bundled 3.0.2
ReShade: 6.8.0 Full Add-On Support, Vulkan, target .trex\NvRemixBridge.exe
DLSS5-Feeder: 0.15.1
LumeniteFX commit: f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9
MV provider: 3 / Lumenite Kernel
nvngx_dlss.dll: 310.9.1
DLAA: mode=2, work_resolution=100
DLSS5 Neural Rendering: NOT INSTALLED
b-bridge clientFrameCap: 0 (uncapped)

Pre-install backup:
$Backup

Runtime proof after launch should include in .trex\dlss5-feed.log:
- DLSS5_MV_PROVIDER=3 (LumeniteFX Kernel)
- NVSDK_NGX_D3D12_Init -> Success
- feature ready: ... DLAA
- frame ... delivered
"@
    [IO.File]::WriteAllText((Join-Path $Game 'DLAA_INSTALL_MANIFEST.txt'), $manifest, (New-Object Text.UTF8Encoding($false)))
    Remove-TemporaryInstallerFiles

    Write-Host ''; Write-Host '========================================================' -ForegroundColor Green; Write-Host ' SUCCESS: GTA IV DLAA STACK INSTALLED' -ForegroundColor Green; Write-Host '========================================================' -ForegroundColor Green
    Write-Host 'Launch GTA IV normally through Steam/Rockstar.' -ForegroundColor White
    Write-Host 'After reaching gameplay, proof is in .trex\dlss5-feed.log' -ForegroundColor Cyan
    Write-Host "Backup: $Backup" -ForegroundColor DarkGray; Write-Host "Install log: $Log" -ForegroundColor DarkGray
    Write-Host 'DLSS5 Neural Rendering was deliberately NOT installed.' -ForegroundColor Yellow
    if ($TranscriptStarted) { Stop-Transcript | Out-Null; $TranscriptStarted = $false }
    Read-Host 'Press Enter to close'; exit 0
}
catch {
    $err = $_.Exception.Message
    Write-Host ''; Write-Host 'INSTALL FAILED:' -ForegroundColor Red; Write-Host $err -ForegroundColor Red; Write-Host 'Attempting automatic rollback to the pre-install FusionFix state...' -ForegroundColor Yellow
    try {
        if ($ReShadeInstalled -and (Test-Path -LiteralPath $ReshadeSetup) -and (Test-Path -LiteralPath (Join-Path $Trex 'NvRemixBridge.exe'))) { $target = Join-Path $Trex 'NvRemixBridge.exe'; Start-Process -FilePath $ReshadeSetup -ArgumentList @("`"$target`"",'--api','vulkan','--headless','--state','uninstall') -Wait | Out-Null }
    } catch { Write-Host 'Warning: automatic ReShade uninstall during rollback failed.' -ForegroundColor Yellow }
    try {
        if (Test-Path -LiteralPath $Trex) { Remove-Item -LiteralPath $Trex -Recurse -Force }
        foreach ($n in @('d3d9.dll','d3d9Hooked.dll','dxvk.conf','commandline.txt')) { $p = Join-Path $Game $n; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
        if ($Backup -and (Test-Path -LiteralPath $Backup)) {
            foreach ($n in @('d3d9.dll','vulkan.dll','dxvk.conf','commandline.txt')) { $src = Join-Path $Backup $n; if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $Game $n) -Force } }
            $cfgBak = Get-ChildItem -LiteralPath (Join-Path $Backup 'plugins') -Filter '*FusionFix*.cfg' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cfgBak -and $ffCfg) { Copy-Item -LiteralPath $cfgBak.FullName -Destination $ffCfg -Force }
            $iniBak = Join-Path $Backup 'plugins\GTAIV.EFLC.FusionFix.ini'; if ((Test-Path -LiteralPath $iniBak) -and $ffIni) { Copy-Item -LiteralPath $iniBak -Destination $ffIni -Force }
        }
        Write-Host 'Rollback completed where possible.' -ForegroundColor Green
    } catch { Write-Host ('Rollback error: ' + $_.Exception.Message) -ForegroundColor Red }
    Remove-TemporaryInstallerFiles
    if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {}; $TranscriptStarted = $false }
    Write-Host "Details were written to: $Log" -ForegroundColor Yellow
    Read-Host 'Press Enter to close'; exit 1
}
