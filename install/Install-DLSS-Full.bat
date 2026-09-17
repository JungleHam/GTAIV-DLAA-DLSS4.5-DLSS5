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
$Temp = Join-Path $env:TEMP ("GTAIV_DLSS_RELEASE_" + $PID)
$Nr50Url = 'https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0/nvngx_dlssnr_310.8.0.zip'
$Nr50PackageHash = '388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC'
$Nr50DllHash = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$Nr40Url = 'https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0-RTX40/nvngx_dlssnr_310.8.0-RTX40.zip'
$Nr40PackageHash = '46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F'
$Nr40DllHash = '4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05'

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
    Write-Host ' GTA IV - DLSS Full + Neural Rendering' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    $Game = Resolve-GameFolder
    if (-not (Test-Path -LiteralPath (Join-Path $Game '.trex\NvRemixBridge.exe'))) { Fail 'DLAA/ReShade step is not detected. Run Install-DLAA.bat first.' }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV first.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe first.' }
    Check-BuildTools

    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
    $gpuName = if ($gpu) { [string]$gpu.Name } else { 'NVIDIA GPU not detected by WMI' }
    if ($gpuName -match 'RTX\s*50') { $flavor='RTX50'; $nrLabel='Original NVIDIA-signed DLSS NR 310.8 (RTX 50)'; $nrUrl=$Nr50Url; $nrPkg=$Nr50PackageHash; $nrDll=$Nr50DllHash }
    elseif ($gpuName -match 'RTX\s*40') { $flavor='RTX40'; $nrLabel='RTX 40 compatibility DLSS NR 310.8 (project-tested)'; $nrUrl=$Nr40Url; $nrPkg=$Nr40PackageHash; $nrDll=$Nr40DllHash }
    else {
        Write-Host ''
        Write-Host "Detected GPU: $gpuName" -ForegroundColor Yellow
        Write-Host 'This release supports Neural Rendering runtime selection for RTX 40 and RTX 50.' -ForegroundColor Yellow
        Write-Host '1 - RTX 50: original NVIDIA-signed runtime'
        Write-Host '2 - RTX 40: compatibility runtime'
        $pick = Read-Host 'Choose 1 or 2'
        if ($pick -eq '1') { $flavor='RTX50'; $nrLabel='Original NVIDIA-signed DLSS NR 310.8 (RTX 50)'; $nrUrl=$Nr50Url; $nrPkg=$Nr50PackageHash; $nrDll=$Nr50DllHash }
        elseif ($pick -eq '2') { $flavor='RTX40'; $nrLabel='RTX 40 compatibility DLSS NR 310.8 (project-tested)'; $nrUrl=$Nr40Url; $nrPkg=$Nr40PackageHash; $nrDll=$Nr40DllHash }
        else { Fail 'No supported Neural Rendering runtime was selected.' }
    }

    Write-Host ''
    Write-Host "Game: $Game"
    Write-Host "GPU:  $gpuName"
    Write-Host "NR:   $nrLabel"
    Write-Host 'DLSS quality default: Quality; Neural Rendering default: OFF.'
    $ok = Read-Host 'Continue? [Y/n]'
    if ($ok -and $ok -notmatch '^(y|yes)$') { exit 0 }

    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    $localCore = Join-Path (Split-Path -Parent $Self) 'core\Install-DLSS-Full-Core.bat'
    $core = Join-Path $Game '_GTAIV_DLSS_Install-DLSS-Full-Core.bat'
    if (Test-Path -LiteralPath $localCore) { Copy-Item -LiteralPath $localCore -Destination $core -Force }
    else { Download "https://raw.githubusercontent.com/$Repo/main/install/core/Install-DLSS-Full-Core.bat" $core }

    # The production core is frozen around the RTX 40 package. For RTX 50, patch only
    # the three verified runtime constants in this temporary copy before executing it.
    if ($flavor -eq 'RTX50') {
        $txt = [IO.File]::ReadAllText($core)
        $txt = $txt.Replace($Nr40Url,$Nr50Url)
        $txt = $txt.Replace($Nr40PackageHash,$Nr50PackageHash)
        $txt = $txt.Replace($Nr40DllHash,$Nr50DllHash)
        $txt = $txt.Replace('nvngx_dlssnr_310.8.0-RTX40.zip','nvngx_dlssnr_310.8.0.zip')
        [IO.File]::WriteAllText($core,$txt,[Text.UTF8Encoding]::new($false))
    }

    $p = Start-Process -FilePath $core -WorkingDirectory $Game -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "DLSS Full installer failed with exit code $($p.ExitCode)." }
    Remove-Item -LiteralPath $core -Force -ErrorAction SilentlyContinue

    $installedNr = Join-Path $Game '.trex\m3k\nvngx_dlssnr.dll'
    if (-not (Test-Path -LiteralPath $installedNr)) { Fail 'Neural Rendering runtime is missing after install.' }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedNr).Hash.ToUpperInvariant()
    if ($actual -ne $nrDll) { Fail "Installed Neural Rendering runtime hash mismatch. Expected $nrDll, got $actual" }
    if ($flavor -eq 'RTX50') {
        $sig = Get-AuthenticodeSignature -LiteralPath $installedNr
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA') { Fail 'RTX 50 Neural Rendering runtime did not pass NVIDIA Authenticode verification.' }
    }
    Add-Content -LiteralPath (Join-Path $Game 'DLSS_FULL_INSTALLED.txt') -Value "NRRuntimeFlavor=$flavor`r`nNRRuntimeLabel=$nrLabel" -Encoding UTF8

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
    Read-Host 'Press Enter to close'
    exit 1
}
finally {
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
