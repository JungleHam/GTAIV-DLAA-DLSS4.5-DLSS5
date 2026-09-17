param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('DLAA','FULL','REMOVE_FULL','REMOVE_ALL')]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$Game
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Fail([string]$Message) { throw $Message }

function Normalize-GamePath([string]$Path) {
    $Path = $Path.Trim().Trim('"')
    if (Test-Path -LiteralPath (Join-Path $Path 'GTAIV.exe')) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    $nested = Join-Path $Path 'GTAIV'
    if (Test-Path -LiteralPath (Join-Path $nested 'GTAIV.exe')) {
        return (Resolve-Path -LiteralPath $nested).Path
    }
    Fail 'GTAIV.exe was not found in the selected folder.'
}

function Test-FusionFixFirstRun([string]$Root) {
    $cfg = 'GTAIV.EFLC.FusionFix.cfg'
    $candidates = @(
        (Join-Path $Root ('plugins\' + $cfg)),
        (Join-Path $Root $cfg),
        (Join-Path $env:LOCALAPPDATA ('Rockstar Games\GTA IV\' + $cfg)),
        (Join-Path $env:LOCALAPPDATA ('GTAIV.EFLC.FusionFix\' + $cfg)),
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('GTAIV.EFLC.FusionFix\' + $cfg))
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $true }
    }
    return $false
}

function Test-DLAA([string]$Root) {
    return (Test-Path -LiteralPath (Join-Path $Root 'DLAA_INSTALL_MANIFEST.txt')) -and
           (Test-Path -LiteralPath (Join-Path $Root '.trex\NvRemixBridge.exe')) -and
           (Test-Path -LiteralPath (Join-Path $Root '.trex\dlss5-feed.addon64'))
}

function Test-Full([string]$Root) {
    return (Test-Path -LiteralPath (Join-Path $Root '.trex\m3k-nr.ini')) -or
           (Test-Path -LiteralPath (Join-Path $Root 'DLSS_FULL_INSTALLED.txt'))
}

function Invoke-InteractiveBat {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [string[]]$InputLines = @()
    )

    if (-not (Test-Path -LiteralPath $Path)) { Fail "Installer component is missing: $Path" }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /c call "' + $Path + '"'
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.CreateNoWindow = $false

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { Fail "Could not start: $Path" }

    foreach ($line in $InputLines) { $proc.StandardInput.WriteLine($line) }
    $proc.StandardInput.Close()
    $proc.WaitForExit()
    $code = $proc.ExitCode
    $proc.Dispose()
    if ($code -ne 0) { Fail "Installer component failed with exit code $code.`n$Path" }
}

function Invoke-DLAA([string]$Root) {
    $script = Join-Path $PSScriptRoot 'Install-DLAA.bat'
    Invoke-InteractiveBat -Path $script -WorkingDirectory $Root -InputLines @($Root, 'y')
}

function Invoke-Full([string]$Root) {
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'NVIDIA' } |
        Select-Object -First 1
    $gpuName = if ($gpu) { [string]$gpu.Name } else { '' }
    if ($gpuName -notmatch 'RTX\s*(40|50)') {
        Fail "Full DLSS release support currently requires an RTX 40 or RTX 50 GPU. Detected: $gpuName"
    }

    $script = Join-Path $PSScriptRoot 'Install-DLSS-Full.bat'
    Invoke-InteractiveBat -Path $script -WorkingDirectory $Root -InputLines @($Root, 'y')
}

function Invoke-RemoveFull([string]$Root) {
    if (-not (Test-Full $Root)) {
        Write-Host 'DLSS Full is not installed; nothing to remove.' -ForegroundColor Yellow
        return
    }

    # The project uninstaller intentionally derives the game path from its own location.
    # Copy the exact bundled uninstaller beside GTAIV.exe, run it, then remove the helper copy.
    $source = Join-Path $PSScriptRoot 'Uninstall-DLSS-Full.bat'
    $tempCopy = Join-Path $Root '_GTAIV_DLSS_MAINTENANCE_Uninstall-Full.bat'
    Copy-Item -LiteralPath $source -Destination $tempCopy -Force
    try {
        Invoke-InteractiveBat -Path $tempCopy -WorkingDirectory $Root
    }
    finally {
        Remove-Item -LiteralPath $tempCopy -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-RemoveAll([string]$Root) {
    if (-not (Test-DLAA $Root) -and -not (Test-Full $Root)) {
        Write-Host 'This project is not detected in the selected GTA IV folder; nothing to remove.' -ForegroundColor Yellow
        return
    }
    $script = Join-Path $PSScriptRoot 'Uninstall-DLAA.bat'
    Invoke-InteractiveBat -Path $script -WorkingDirectory $Root -InputLines @($Root, 'y')
}

$Game = Normalize-GamePath $Game
if (-not (Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))) {
    Fail 'FusionFix is not detected (dinput8.dll is missing). Install FusionFix first.'
}
if (($Action -eq 'DLAA' -or $Action -eq 'FULL') -and -not (Test-FusionFixFirstRun $Game)) {
    Fail 'FusionFix is installed, but its first-run runtime file was not found. Launch GTA IV normally once with FusionFix installed, wait until the main menu appears, close the game, then run setup again.'
}
if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before continuing.' }
if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before continuing.' }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' GTA IV DLSS Setup & Maintenance' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host "Game: $Game"
Write-Host "Action: $Action"
Write-Host ''

switch ($Action) {
    'DLAA' {
        if (Test-Full $Game) {
            Write-Host 'DLSS Full detected. Returning to the DLAA baseline first...' -ForegroundColor Cyan
            Invoke-RemoveFull $Game
        }
        Invoke-DLAA $Game
    }
    'FULL' {
        if (-not (Test-DLAA $Game)) {
            Write-Host 'DLAA foundation is not installed. Installing it automatically first...' -ForegroundColor Cyan
            Invoke-DLAA $Game
        }
        Invoke-Full $Game
    }
    'REMOVE_FULL' {
        Invoke-RemoveFull $Game
    }
    'REMOVE_ALL' {
        Invoke-RemoveAll $Game
    }
}

Write-Host ''
Write-Host 'ACTION COMPLETED SUCCESSFULLY.' -ForegroundColor Green
exit 0
