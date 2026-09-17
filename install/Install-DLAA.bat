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
$PatchCommit = 'b437e7646b262dc60863293348fd33369330a429'
$Temp = Join-Path $env:TEMP ("GTAIV_DLAA_RELEASE_" + $PID)

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
    if (-not (Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))) { Fail 'FusionFix is not detected. Install FusionFix first.' }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV first.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe first.' }
    Check-BuildTools

    Write-Host ''
    Write-Host "Game: $Game"
    Write-Host 'This installs the DLAA baseline and the ReShade Home/mouse/keyboard patch.'
    $ok = Read-Host 'Continue? [Y/n]'
    if ($ok -and $ok -notmatch '^(y|yes)$') { exit 0 }

    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    $localCore = Join-Path (Split-Path -Parent $Self) 'core\Install-DLAA-Core.bat'
    $core = Join-Path $Game '_GTAIV_DLSS_Install-DLAA-Core.bat'
    if (Test-Path -LiteralPath $localCore) { Copy-Item -LiteralPath $localCore -Destination $core -Force }
    else { Download "https://raw.githubusercontent.com/$Repo/main/install/core/Install-DLAA-Core.bat" $core }
    # The legacy core pauses at its own end. The release wrapper owns the UX, so remove only those close prompts from this temporary copy.
    $coreText = [IO.File]::ReadAllText($core)
    $coreText = $coreText.Replace("    Read-Host 'Press Enter to close'; exit 0", '    exit 0')
    $coreText = $coreText.Replace("    Read-Host 'Press Enter to close'; exit 1", '    exit 1')
    [IO.File]::WriteAllText($core,$coreText,[Text.UTF8Encoding]::new($false))

    Write-Host ''
    Write-Host '[1/2] Installing DLAA baseline...' -ForegroundColor Cyan
    $p = Start-Process -FilePath $core -WorkingDirectory $Game -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "DLAA installer failed with exit code $($p.ExitCode)." }
    Remove-Item -LiteralPath $core -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host '[2/2] Building and installing the ReShade input patch...' -ForegroundColor Cyan
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
    $p = Start-Process -FilePath (Join-Path $patchDir 'BUILD.bat') -WorkingDirectory $patchDir -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail 'ReShade input patch build failed.' }
    $p = Start-Process -FilePath (Join-Path $patchDir 'INSTALL.bat') -ArgumentList ('"' + $Game + '"') -WorkingDirectory $patchDir -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail 'ReShade input patch install failed.' }

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
    Write-Host 'No further step was started.' -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit 1
}
finally {
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
