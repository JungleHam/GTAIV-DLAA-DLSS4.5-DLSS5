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
$PatchCommit = 'b437e7646b262dc60863293348fd33369330a429'
$Temp = Join-Path $env:TEMP ("GTAIV_DLAA_RELEASE_" + $PID)
$CoreTemp = $null

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Fail([string]$m) { throw $m }
function Download([string]$u,[string]$p) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) { & curl.exe -L --fail --retry 3 --connect-timeout 20 --silent --show-error -o $p $u; if ($LASTEXITCODE -ne 0) { Fail "Download failed: $u" } }
    else { Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p }
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
function Check-BuildTools {
    $missing = @()
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { $missing += 'Git for Windows: https://git-scm.com/download/win' }
    if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) { $missing += 'Python 3 (enable Add python.exe to PATH): https://www.python.org/downloads/windows/' }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsOk = $false
    if (Test-Path -LiteralPath $vswhere) {
        $root = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1)
        $vsOk = -not [string]::IsNullOrWhiteSpace($root)
    }
    if (-not $vsOk) { $missing += 'Visual Studio 2022 Build Tools -> Desktop development with C++: https://aka.ms/vs/17/release/vs_BuildTools.exe' }
    if ($missing.Count) { Fail ("Missing prerequisite(s):`n  - " + ($missing -join "`n  - ")) }
}
function Has-PatchMarker([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($path))
        return $ascii.Contains('b-bridge input relay')
    } catch { return $false }
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
    Check-BuildTools

    $dlaaReady = (Test-Path -LiteralPath (Join-Path $Trex 'NvRemixBridge.exe')) -and
                 (Test-Path -LiteralPath (Join-Path $Trex 'dlss5-feed.addon64')) -and
                 (Test-Path -LiteralPath (Join-Path $Game 'DLAA_INSTALL_MANIFEST.txt'))
    $reshadePatchedBefore = Has-PatchMarker 'C:\ProgramData\ReShade\ReShade64.dll'

    Write-Host ''
    Write-Host "Game: $Game"
    Write-Host ("DLAA baseline: " + $(if ($dlaaReady) { 'already installed - will keep it' } else { 'will install' }))
    Write-Host ("System-wide ReShade input patch: " + $(if ($reshadePatchedBefore) { 'currently detected - will verify again after DLAA/ReShade install' } else { 'not detected - will verify/build after DLAA/ReShade install' }))
    $ok = Read-Host 'Continue? [Y/n]'
    if ($ok -and $ok -notmatch '^(y|yes)$') { exit 0 }

    New-Item -ItemType Directory -Path $Temp -Force | Out-Null

    if (-not $dlaaReady) {
        Write-Host ''
        Write-Host '[1/2] Installing DLAA baseline...' -ForegroundColor Cyan
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

    # Re-check after the DLAA core because ReShade setup can refresh the global Vulkan-layer DLL.
    $reshadePatched = Has-PatchMarker 'C:\ProgramData\ReShade\ReShade64.dll'
    Write-Host ("[2/2] System-wide ReShade input patch after DLAA/ReShade install: " + $(if ($reshadePatched) { 'detected' } else { 'not detected - installing now' }))

    if (-not $reshadePatched) {
        Write-Host ''
        Write-Host '[2/2] Building and installing the ReShade input patch...' -ForegroundColor Cyan
        Write-Host '      ReShade is compiled from source here; this can take several minutes.' -ForegroundColor DarkGray
        Write-Host '      Build progress will be shown below.' -ForegroundColor DarkGray
        $patchDir = Join-Path $Temp 'reshade-input'
        New-Item -ItemType Directory -Path $patchDir -Force | Out-Null
        $base = "https://raw.githubusercontent.com/$Repo/$PatchCommit/tools/reshade-bbridge-input"
        foreach ($name in @('BUILD.bat','INSTALL.bat','apply_patch.ps1')) { Download "$base/$name" (Join-Path $patchDir $name) }
        foreach ($name in @('BUILD.bat','INSTALL.bat')) {
            $path = Join-Path $patchDir $name
            $txt = [IO.File]::ReadAllText($path)
            $txt = [regex]::Replace($txt,'(?m)^\s*pause\s*$','rem pause')
            [IO.File]::WriteAllText($path,$txt,[Text.UTF8Encoding]::new($false))
        }

        $buildBat = Join-Path $patchDir 'BUILD.bat'
        Push-Location $patchDir
        try {
            & $buildBat
            $buildExit = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        if ($buildExit -ne 0) { Fail "ReShade input patch build failed with exit code $buildExit. Re-run this same installer after fixing the shown prerequisite/build error; it will keep the completed DLAA baseline." }

        Write-Host ''
        Write-Host '[2/2] Build complete. Installing the patched ReShade DLL...' -ForegroundColor Cyan
        $installBat = Join-Path $patchDir 'INSTALL.bat'
        Push-Location $patchDir
        try {
            & $installBat $Game
            $installExit = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        if ($installExit -ne 0) { Fail "ReShade input patch install failed with exit code $installExit. Re-run this same installer; it will keep the completed DLAA baseline." }
    } else {
        Write-Host '[2/2] System-wide ReShade input patch is already active; skipping rebuild.' -ForegroundColor Green
    }

    if (-not (Has-PatchMarker 'C:\ProgramData\ReShade\ReShade64.dll')) { Fail 'Final ReShade input-patch verification failed.' }
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
