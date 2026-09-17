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
$ReleaseCoreCommit = '7968ba5dc0c9dcbb70c1ff98b37441a9687fc9ff'
$RuntimeTag = 'runtime-prebuilt-v1'
$PatchedReShadeUrl = "https://github.com/$Repo/releases/download/$RuntimeTag/ReShade64-bbridge.dll"
$PatchedReShadeHash = '75976007A0A5DE5BAB364F98E2D01B377D046441C94E89B1DD279CEE856161A9'
$GlobalReShade = 'C:\ProgramData\ReShade\ReShade64.dll'
$GlobalReShadeBackup = 'C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input'
$Temp = Join-Path $env:TEMP ("GTAIV_DLAA_RELEASE_" + $PID)
$CoreTemp = $null

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
function Assert-SHA256([string]$p,[string]$expected) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant()
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
function Has-PatchMarker([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($path))
        return $ascii.Contains('b-bridge input relay')
    } catch { return $false }
}
function Set-KeyEquals([string]$Path,[string]$Key,[string]$Value) {
    $text = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
    $pat = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*.*$'
    $line = "$Key = $Value"
    if ($text -match $pat) { $text = [regex]::Replace($text,$pat,$line) }
    else {
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`r`n" }
        $text += $line + "`r`n"
    }
    [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}
function Ensure-ReShade([string]$Game,[string]$Trex) {
    if ((Test-Path -LiteralPath $GlobalReShade) -and (Test-Path -LiteralPath (Join-Path $Trex 'ReShade.ini'))) { return }
    Write-Host '[2/2] ReShade Vulkan layer is missing; reinstalling official ReShade 6.8.0 Add-On Support...' -ForegroundColor Cyan
    $setup = Join-Path $Temp 'ReShade_Setup_6.8.0_Addon.exe'
    try { Download 'https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe' $setup }
    catch { Download 'https://www.reshade.me/releases/ReShade-6.8.0-Addon-setup.exe' $setup }
    if ((Get-Item -LiteralPath $setup).Length -lt 1MB) { Fail 'ReShade setup download is unexpectedly small.' }
    $target = Join-Path $Trex 'NvRemixBridge.exe'
    if (-not (Test-Path -LiteralPath $target)) { Fail 'NvRemixBridge.exe is missing; reinstall the DLAA baseline first.' }
    $p = Start-Process -FilePath $setup -ArgumentList @("`"$target`"",'--api','vulkan','--headless') -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "Official ReShade setup failed with exit code $($p.ExitCode)." }
    if (-not (Test-Path -LiteralPath $GlobalReShade)) { Fail 'Official ReShade Vulkan DLL was not installed.' }
}

if (-not (Is-Admin)) {
    Write-Host 'Administrator permission is required. Approve the Windows prompt.' -ForegroundColor Yellow
    $p = Start-Process -FilePath $Self -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}

try {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' GTA IV - DLAA + ReShade input patch' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    $Game = Resolve-GameFolder
    $Trex = Join-Path $Game '.trex'
    if (-not (Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))) { Fail 'FusionFix is not detected. Install FusionFix first.' }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV first.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe first.' }
    if (Test-Path -LiteralPath (Join-Path $Trex 'm3k-nr.ini')) { Fail 'DLSS Full is already installed. Do not run the DLAA baseline installer over it.' }

    $dlaaReady = (Test-Path -LiteralPath (Join-Path $Trex 'NvRemixBridge.exe')) -and
                 (Test-Path -LiteralPath (Join-Path $Trex 'dlss5-feed.addon64')) -and
                 (Test-Path -LiteralPath (Join-Path $Game 'DLAA_INSTALL_MANIFEST.txt'))
    $reshadePatchedBefore = Has-PatchMarker $GlobalReShade

    Write-Host ''
    Write-Host "Game: $Game"
    Write-Host ("DLAA baseline: " + $(if ($dlaaReady) { 'already installed - will keep it' } else { 'will install' }))
    Write-Host ("System-wide ReShade input patch: " + $(if ($reshadePatchedBefore) { 'already installed' } else { 'will install from verified prebuilt release' }))
    Write-Host 'No Git, Python or Visual Studio build tools are required.' -ForegroundColor Green
    $ok = Read-Host 'Continue? [Y/n]'
    if ($ok -and $ok -notmatch '^(y|yes)$') { exit 0 }

    New-Item -ItemType Directory -Path $Temp -Force | Out-Null

    if (-not $dlaaReady) {
        Write-Host ''
        Write-Host '[1/2] Installing DLAA baseline + official ReShade...' -ForegroundColor Cyan
        $localCore = Join-Path (Split-Path -Parent $Self) 'core\Install-DLAA-Core.bat'
        $CoreTemp = Join-Path $Game '_GTAIV_DLSS_Install-DLAA-Core.bat'
        if (Test-Path -LiteralPath $localCore) { Copy-Item -LiteralPath $localCore -Destination $CoreTemp -Force }
        else { Download "https://raw.githubusercontent.com/$Repo/$ReleaseCoreCommit/install/core/Install-DLAA-Core.bat" $CoreTemp }
        $coreText = [IO.File]::ReadAllText($CoreTemp)
        $coreText = $coreText.Replace("    Read-Host 'Press Enter to close'; exit 0", '    exit 0')
        $coreText = $coreText.Replace("    Read-Host 'Press Enter to close'; exit 1", '    exit 1')
        [IO.File]::WriteAllText($CoreTemp,$coreText,[Text.UTF8Encoding]::new($false))
        $p = Start-Process -FilePath $CoreTemp -WorkingDirectory $Game -Wait -PassThru
        if ($p.ExitCode -ne 0) { Fail "DLAA installer failed with exit code $($p.ExitCode)." }
        Remove-Item -LiteralPath $CoreTemp -Force -ErrorAction SilentlyContinue
        $CoreTemp = $null
    } else {
        Write-Host '[1/2] Existing DLAA baseline detected; skipping reinstall.' -ForegroundColor Green
    }

    Ensure-ReShade $Game $Trex
    $reshadePatched = Has-PatchMarker $GlobalReShade
    if (-not $reshadePatched) {
        Write-Host ''
        Write-Host '[2/2] Installing verified prebuilt ReShade input patch...' -ForegroundColor Cyan
        $patched = Join-Path $Temp 'ReShade64-bbridge.dll'
        Download $PatchedReShadeUrl $patched
        Assert-SHA256 $patched $PatchedReShadeHash
        if (-not (Has-PatchMarker $patched)) { Fail 'Downloaded ReShade64-bbridge.dll is missing the expected patch marker.' }

        if (-not (Test-Path -LiteralPath $GlobalReShadeBackup)) {
            Copy-Item -LiteralPath $GlobalReShade -Destination $GlobalReShadeBackup -Force
        }
        Copy-Item -LiteralPath $patched -Destination $GlobalReShade -Force
        Assert-SHA256 $GlobalReShade $PatchedReShadeHash

        $bridgeConf = Join-Path $Trex 'bridge.conf'
        if (-not (Test-Path -LiteralPath $bridgeConf)) { Fail 'bridge.conf is missing.' }
        Set-KeyEquals $bridgeConf 'client.DirectInput.forward.mousePolicy' '3'
        Set-KeyEquals $bridgeConf 'client.DirectInput.forward.keyboardPolicy' '3'
    } else {
        Write-Host '[2/2] System-wide ReShade input patch already active; nothing to rebuild.' -ForegroundColor Green
    }

    if (-not (Has-PatchMarker $GlobalReShade)) { Fail 'Final ReShade input-patch verification failed.' }
    Write-Host ''
    Write-Host 'DONE - DLAA + ReShade input patch installed.' -ForegroundColor Green
    Write-Host 'Launch GTA IV once. Press Home and confirm ReShade opens and accepts mouse/keyboard input.' -ForegroundColor White
    Write-Host 'Then run Install-DLSS-Full.bat as Administrator.' -ForegroundColor Cyan
    Start-Sleep -Seconds 4
    exit 0
}
catch {
    Write-Host ''
    Write-Host ('INSTALL FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
finally {
    if ($CoreTemp -and (Test-Path -LiteralPath $CoreTemp)) { Remove-Item -LiteralPath $CoreTemp -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
