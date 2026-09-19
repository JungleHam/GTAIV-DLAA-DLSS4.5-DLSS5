param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('DLAA','FULL','REMOVE_FULL','REMOVE_ALL')]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$Game,

    [string]$FusionFixPackage = '',
    [string]$ReShadeSetup = '',
    [string]$LumenitePackage = '',
    [string]$NrPackage = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Fail([string]$Message) { throw $Message }

function Normalize-GamePath([string]$Path) {
    $Path = $Path.Trim().Trim('"')
    if (Test-Path -LiteralPath (Join-Path $Path 'GTAIV.exe')) { return (Resolve-Path -LiteralPath $Path).Path }
    $nested = Join-Path $Path 'GTAIV'
    if (Test-Path -LiteralPath (Join-Path $nested 'GTAIV.exe')) { return (Resolve-Path -LiteralPath $nested).Path }
    Fail 'GTAIV.exe was not found in the selected folder.'
}

function Test-FusionFixFirstRun([string]$Root) {
    $cfg = 'GTAIV.EFLC.FusionFix.cfg'
    $candidates = @(
        (Join-Path $Root ('plugins\\' + $cfg)),
        (Join-Path $Root $cfg),
        (Join-Path $env:LOCALAPPDATA ('Rockstar Games\\GTA IV\\' + $cfg)),
        (Join-Path $env:LOCALAPPDATA ('GTAIV.EFLC.FusionFix\\' + $cfg)),
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('GTAIV.EFLC.FusionFix\\' + $cfg))
    )
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $true } }
    return $false
}

function Test-DLAA([string]$Root) {
    return (Test-Path -LiteralPath (Join-Path $Root 'DLAA_INSTALL_MANIFEST.txt')) -and
           (Test-Path -LiteralPath (Join-Path $Root '.trex\\NvRemixBridge.exe')) -and
           (Test-Path -LiteralPath (Join-Path $Root '.trex\\dlss5-feed.addon64'))
}
function Test-Full([string]$Root) {
    return (Test-Path -LiteralPath (Join-Path $Root '.trex\\m3k-nr.ini')) -or
           (Test-Path -LiteralPath (Join-Path $Root 'DLSS_FULL_INSTALLED.txt'))
}

function Require-InputFile([string]$Path,[string]$Label) {
    if (-not $Path) { Fail "$Label was not selected." }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail "$Label was not found: $Path" }
    return (Resolve-Path -LiteralPath $Path).Path
}


function Assert-SHA256([string]$Path,[string]$Expected,[string]$Label) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
    if ($actual -ne $Expected.ToUpperInvariant()) { Fail "$Label SHA256 did not match the tested file.`nExpected: $Expected`nActual:   $actual" }
}

function Install-FusionFixPackage([string]$Root,[string]$Path) {
    $input = Require-InputFile $Path 'FusionFix 5.0.1 ZIP'
    $expected = '3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41'
    Assert-SHA256 $input $expected 'FusionFix 5.0.1 ZIP'
    $temp = Join-Path $env:TEMP ('GTAIV_FUSIONFIX_' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        Expand-Archive -LiteralPath $input -DestinationPath $temp -Force
        $dinputs = @(Get-ChildItem -LiteralPath $temp -Recurse -File -Filter 'dinput8.dll')
        if ($dinputs.Count -lt 1) { Fail 'The selected FusionFix ZIP does not contain dinput8.dll.' }
        $packageRoot = $dinputs[0].Directory.FullName
        Get-ChildItem -LiteralPath $packageRoot -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $Root -Recurse -Force
        }
        if (-not (Test-Path -LiteralPath (Join-Path $Root 'dinput8.dll'))) { Fail 'FusionFix extraction completed, but dinput8.dll is still missing from the GTA IV folder.' }
        [IO.File]::WriteAllText((Join-Path $Root 'GTAIV_DLSS_FUSIONFIX_INSTALLED_BY_SETUP.txt'), "FusionFix 5.0.1 installed by GTA IV DLSS setup from user-supplied ZIP.`r`n", [Text.UTF8Encoding]::new($false))
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}



$script:NrExtractTemp = $null
function Resolve-NrPackage([string]$Path) {
    $input = Require-InputFile $Path 'Neural Rendering package'
    $ext = [IO.Path]::GetExtension($input).ToLowerInvariant()
    if ($ext -eq '.dll') { return $input }
    if ($ext -ne '.zip') { Fail 'Neural Rendering input must be the downloaded ZIP or nvngx_dlssnr.dll.' }

    $script:NrExtractTemp = Join-Path $env:TEMP ('GTAIV_DLSS_NR_' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $script:NrExtractTemp -Force | Out-Null
        Expand-Archive -LiteralPath $input -DestinationPath $script:NrExtractTemp -Force
        $dlls = @(Get-ChildItem -LiteralPath $script:NrExtractTemp -Recurse -File -Filter 'nvngx_dlssnr.dll')
        if ($dlls.Count -ne 1) { Fail "The selected NR ZIP must contain exactly one nvngx_dlssnr.dll. Found: $($dlls.Count)" }
        return $dlls[0].FullName
    }
    catch {
        if ($script:NrExtractTemp -and (Test-Path -LiteralPath $script:NrExtractTemp)) {
            Remove-Item -LiteralPath $script:NrExtractTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:NrExtractTemp = $null
        throw
    }
}

function Prepare-NonInteractiveBat {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Root)
    $text = [IO.File]::ReadAllText($Path)
    $text = $text.Replace('$Game = Resolve-GameFolder', '$Game = $env:GTAIV_SETUP_GAME')
    $text = $text.Replace('$ok = Read-Host ''Continue? [Y/n]''', '$ok = ''y''')
    $text = $text.Replace('$ok = Read-Host ''Continue? [y/N]''', '$ok = ''y''')
    $text = $text.Replace('Read-Host ''Press Enter to close''', '$null = $null')
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
    $env:GTAIV_SETUP_GAME = $Root
}

function Invoke-BundledBat {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$WorkingDirectory,[switch]$NonInteractive)
    if (-not (Test-Path -LiteralPath $Path)) { Fail "Installer component is missing: $Path" }
    if ($NonInteractive) { Prepare-NonInteractiveBat -Path $Path -Root $WorkingDirectory }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /c call "' + $Path + '"'
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.CreateNoWindow = $false
    if ($NonInteractive) { $psi.EnvironmentVariables['GTAIV_SETUP_GAME'] = $WorkingDirectory }
    if ($env:GTAIV_SETUP_RESHADE) { $psi.EnvironmentVariables['GTAIV_SETUP_RESHADE'] = $env:GTAIV_SETUP_RESHADE }
    if ($env:GTAIV_SETUP_LUMENITE) { $psi.EnvironmentVariables['GTAIV_SETUP_LUMENITE'] = $env:GTAIV_SETUP_LUMENITE }
    if ($env:GTAIV_SETUP_NR_DLL) { $psi.EnvironmentVariables['GTAIV_SETUP_NR_DLL'] = $env:GTAIV_SETUP_NR_DLL }
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { Fail "Could not start: $Path" }
    $proc.WaitForExit(); $code = $proc.ExitCode; $proc.Dispose()
    if ($code -ne 0) { Fail "Installer component failed with exit code $code.`n$Path" }
}

function Invoke-DLAA([string]$Root) {
    $script = Join-Path $PSScriptRoot 'Install-DLAA.bat'
    Invoke-BundledBat -Path $script -WorkingDirectory $Root -NonInteractive
}
function Invoke-Full([string]$Root) {
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
    $gpuName = if ($gpu) { [string]$gpu.Name } else { '' }
    if ($gpuName -notmatch 'RTX\s*(40|50)') { Fail "Full DLSS release support currently requires an RTX 40 or RTX 50 GPU. Detected: $gpuName" }
    $script = Join-Path $PSScriptRoot 'Install-DLSS-Full.bat'
    Invoke-BundledBat -Path $script -WorkingDirectory $Root -NonInteractive
}
function Invoke-RemoveFull([string]$Root) {
    if (-not (Test-Full $Root)) { Write-Host 'DLSS Full is not installed; nothing to remove.' -ForegroundColor Yellow; return }
    $source = Join-Path $PSScriptRoot 'Uninstall-DLSS-Full.bat'
    $tempCopy = Join-Path $Root '_GTAIV_DLSS_MAINTENANCE_Uninstall-Full.bat'
    Copy-Item -LiteralPath $source -Destination $tempCopy -Force
    try { Invoke-BundledBat -Path $tempCopy -WorkingDirectory $Root }
    finally { Remove-Item -LiteralPath $tempCopy -Force -ErrorAction SilentlyContinue }
}
function Invoke-RemoveAll([string]$Root) {
    if (-not (Test-DLAA $Root) -and -not (Test-Full $Root)) { Write-Host 'This project is not detected in the selected GTA IV folder; nothing to remove.' -ForegroundColor Yellow; return }
    $script = Join-Path $PSScriptRoot 'Uninstall-DLAA.bat'
    Invoke-BundledBat -Path $script -WorkingDirectory $Root -NonInteractive
}

$Game = Normalize-GamePath $Game
if (-not (Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))) {
    if ($Action -eq 'REMOVE_FULL' -or $Action -eq 'REMOVE_ALL') { Fail 'FusionFix is not detected and there is no supported installation state to remove.' }
    Install-FusionFixPackage -Root $Game -Path $FusionFixPackage
    Write-Host ''
    Write-Host 'FUSIONFIX INSTALLED.' -ForegroundColor Green
    Write-Host 'Launch GTA IV normally once, wait until the main menu appears, then close the game.' -ForegroundColor Yellow
    Write-Host 'After that, run GTAIV-DLSS-Setup.exe again from the same prerequisite folder. Do not install or extract the other downloaded files yourself.' -ForegroundColor Yellow
    exit 20
}
if (($Action -eq 'DLAA' -or $Action -eq 'FULL') -and -not (Test-FusionFixFirstRun $Game)) { Fail 'FusionFix is installed, but its first-run runtime file was not found. Launch GTA IV normally once with FusionFix installed, wait until the main menu appears, close the game, then run setup again from the same prerequisite folder.' }
if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before continuing.' }
if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before continuing.' }

$needsFoundationInputs = ($Action -eq 'DLAA') -or (($Action -eq 'FULL') -and -not (Test-DLAA $Game))
if ($needsFoundationInputs) {
    $env:GTAIV_SETUP_RESHADE = Require-InputFile $ReShadeSetup 'Official ReShade 6.8.0 Add-On installer'
    $env:GTAIV_SETUP_LUMENITE = Require-InputFile $LumenitePackage 'LumeniteFX ZIP'
}
if ($Action -eq 'FULL') { $env:GTAIV_SETUP_NR_DLL = Resolve-NrPackage $NrPackage }

Write-Host ''; Write-Host '============================================================' -ForegroundColor Green
Write-Host ' GTA IV DLSS Setup & Maintenance' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Game: $Game"; Write-Host "Action: $Action"; Write-Host ''

try {
    switch ($Action) {
        'DLAA' { if (Test-Full $Game) { Write-Host 'DLSS Full detected. Returning to the DLAA baseline first...' -ForegroundColor Cyan; Invoke-RemoveFull $Game }; Invoke-DLAA $Game }
        'FULL' { if (-not (Test-DLAA $Game)) { Write-Host 'DLAA foundation is not installed. Installing it automatically first...' -ForegroundColor Cyan; Invoke-DLAA $Game }; Invoke-Full $Game }
        'REMOVE_FULL' { Invoke-RemoveFull $Game }
        'REMOVE_ALL' { Invoke-RemoveAll $Game }
    }
    Write-Host ''; Write-Host 'ACTION COMPLETED SUCCESSFULLY.' -ForegroundColor Green
}
finally {
    if ($script:NrExtractTemp -and (Test-Path -LiteralPath $script:NrExtractTemp)) {
        Remove-Item -LiteralPath $script:NrExtractTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
