param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('DLAA','FULL','REMOVE_FULL','REMOVE_ALL')]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$Game,

    [string]$FusionFixPackage = '',
    [string]$ReShadeSetup = '',
    [string]$LumenitePackage = '',
    [string]$NrPackage = '',
    [string]$SetupSource = '',
    [string]$ResultFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:AutoTemp = $null

function Write-Result([string]$Text) {
    if (-not $ResultFile) { return }
    try { [IO.File]::WriteAllText($ResultFile, $Text, [Text.UTF8Encoding]::new($false)) } catch {}
}

if ($SetupSource -and (Test-Path -LiteralPath $SetupSource -PathType Container)) {
    $candidateRuntime = Join-Path $SetupSource 'GTAIV-DLSS-Full-Runtime.zip'
    $candidatePatch = Join-Path $SetupSource 'ReShade64-bbridge.dll'
    if (Test-Path -LiteralPath $candidateRuntime -PathType Leaf) { $env:GTAIV_SETUP_PROJECT_RUNTIME = (Resolve-Path -LiteralPath $candidateRuntime).Path }
    if (Test-Path -LiteralPath $candidatePatch -PathType Leaf) { $env:GTAIV_SETUP_RESHADE_PATCH = (Resolve-Path -LiteralPath $candidatePatch).Path }
}

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

function Get-AutoTemp {
    if (-not $script:AutoTemp) {
        $script:AutoTemp = Join-Path $env:TEMP ('GTAIV_DLSS_AUTO_' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:AutoTemp -Force | Out-Null
    }
    return $script:AutoTemp
}

function Download-GitHubUrl([string]$Uri,[string]$Destination,[string]$Label) {
    Write-Host "Downloading $Label from GitHub..." -ForegroundColor Cyan
    $headers = @{ 'User-Agent' = 'GTAIV-DLSS-Setup' }
    try { Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $Uri -OutFile $Destination }
    catch { Fail "Could not download $Label from GitHub. $($_.Exception.Message)" }
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) { Fail "$Label download did not create a file." }
}

function Download-GitHubReleaseAsset([string]$Repo,[string]$Tag,[string]$Asset,[string]$Destination,[string]$Label) {
    $headers = @{ 'User-Agent' = 'GTAIV-DLSS-Setup'; 'Accept' = 'application/vnd.github+json' }
    $api = "https://api.github.com/repos/$Repo/releases/tags/$Tag"
    try { $release = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri $api }
    catch { Fail "Could not read the GitHub release for $Label. $($_.Exception.Message)" }
    $match = @($release.assets | Where-Object { $_.name -eq $Asset }) | Select-Object -First 1
    if (-not $match -or -not $match.browser_download_url) { Fail "GitHub release asset was not found: $Repo / $Tag / $Asset" }
    Download-GitHubUrl -Uri ([string]$match.browser_download_url) -Destination $Destination -Label $Label
    return $Destination
}

function Find-BesideSetup([string]$FileName) {
    if (-not $SetupSource) { return $null }
    $p = Join-Path $SetupSource $FileName
    if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path }
    return $null
}

function Resolve-FusionFixPackage {
    if ($FusionFixPackage -and (Test-Path -LiteralPath $FusionFixPackage -PathType Leaf)) { return (Resolve-Path -LiteralPath $FusionFixPackage).Path }
    $local = Find-BesideSetup 'GTAIV.EFLC.FusionFix.zip'
    if ($local) { return $local }
    $dest = Join-Path (Get-AutoTemp) 'GTAIV.EFLC.FusionFix.zip'
    return Download-GitHubReleaseAsset -Repo 'ThirteenAG/GTAIV.EFLC.FusionFix' -Tag 'v5.0.1' -Asset 'GTAIV.EFLC.FusionFix.zip' -Destination $dest -Label 'FusionFix 5.0.1'
}

function Resolve-LumenitePackage {
    if ($LumenitePackage -and (Test-Path -LiteralPath $LumenitePackage -PathType Leaf)) { return (Resolve-Path -LiteralPath $LumenitePackage).Path }
    $name = 'LumeniteFX-f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9.zip'
    $dest = Join-Path (Get-AutoTemp) $name
    $uri = 'https://api.github.com/repos/umar-afzaal/LumeniteFX/zipball/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9'
    Download-GitHubUrl -Uri $uri -Destination $dest -Label 'pinned LumeniteFX'
    return $dest
}

function Get-GpuInfo {
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
    $name = if ($gpu) { [string]$gpu.Name } else { '' }
    $series = 0
    if ($name -match 'RTX\s*50') { $series = 50 }
    elseif ($name -match 'RTX\s*40') { $series = 40 }
    return [pscustomobject]@{ Name=$name; Series=$series }
}

function Resolve-AutoNrPackage {
    $gpu = Get-GpuInfo
    if ($gpu.Series -eq 40) { $tag='dlssnr-310.8.0-RTX40'; $asset='nvngx_dlssnr_310.8.0-RTX40.zip'; $label='DLSS NR 310.8.0 RTX 40 compatibility package' }
    elseif ($gpu.Series -eq 50) { $tag='dlssnr-310.8.0'; $asset='nvngx_dlssnr_310.8.0.zip'; $label='DLSS NR 310.8.0 RTX 50 package' }
    else { Fail "Full DLSS currently supports RTX 40/50. Detected: $($gpu.Name)" }
    $local = Find-BesideSetup $asset
    if ($local) { return $local }
    $dest = Join-Path (Get-AutoTemp) $asset
    return Download-GitHubReleaseAsset -Repo 'RankFTW/rhi-repo' -Tag $tag -Asset $asset -Destination $dest -Label $label
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
        [IO.File]::WriteAllText((Join-Path $Root 'GTAIV_DLSS_FUSIONFIX_INSTALLED_BY_SETUP.txt'), "FusionFix 5.0.1 downloaded from the official GitHub release and installed by GTA IV DLSS setup.`r`n", [Text.UTF8Encoding]::new($false))
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
    if ($env:GTAIV_SETUP_PROJECT_RUNTIME) { $psi.EnvironmentVariables['GTAIV_SETUP_PROJECT_RUNTIME'] = $env:GTAIV_SETUP_PROJECT_RUNTIME }
    if ($env:GTAIV_SETUP_RESHADE_PATCH) { $psi.EnvironmentVariables['GTAIV_SETUP_RESHADE_PATCH'] = $env:GTAIV_SETUP_RESHADE_PATCH }
    if ($ResultFile) { $psi.EnvironmentVariables['GTAIV_SETUP_RESULT_FILE'] = $ResultFile }
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { Fail "Could not start: $Path" }
    $proc.WaitForExit(); $code = $proc.ExitCode; $proc.Dispose()
    if ($code -ne 0) {
        if ($ResultFile -and (Test-Path -LiteralPath $ResultFile -PathType Leaf)) {
            $detail = [IO.File]::ReadAllText($ResultFile).Trim()
            if ($detail) { Fail $detail }
        }
        Fail "Installer component failed with exit code ${code}: $([IO.Path]::GetFileName($Path))"
    }
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

trap {
    $message = $_.Exception.Message
    Write-Host ''
    Write-Host ('INSTALL FAILED: ' + $message) -ForegroundColor Red
    Write-Result $message
    if ($script:NrExtractTemp -and (Test-Path -LiteralPath $script:NrExtractTemp)) { Remove-Item -LiteralPath $script:NrExtractTemp -Recurse -Force -ErrorAction SilentlyContinue }
    if ($script:AutoTemp -and (Test-Path -LiteralPath $script:AutoTemp)) { Remove-Item -LiteralPath $script:AutoTemp -Recurse -Force -ErrorAction SilentlyContinue }
    exit 1
}

$Game = Normalize-GamePath $Game
if (-not (Test-Path -LiteralPath (Join-Path $Game 'dinput8.dll'))) {
    if ($Action -eq 'REMOVE_FULL' -or $Action -eq 'REMOVE_ALL') { Fail 'FusionFix is not detected and there is no supported installation state to remove.' }
    $ffPackage = Resolve-FusionFixPackage
    Install-FusionFixPackage -Root $Game -Path $ffPackage
    Write-Host ''
    Write-Host 'FUSIONFIX INSTALLED.' -ForegroundColor Green
    Write-Host 'Launch GTA IV normally once, wait until the main menu appears, then close the game.' -ForegroundColor Yellow
    Write-Host 'After that, run GTAIV-DLSS-Setup.exe again. GitHub prerequisites are downloaded automatically.' -ForegroundColor Yellow
    Write-Result 'FusionFix 5.0.1 was installed automatically. Launch GTA IV once to the main menu, close it, then run this setup again.'
    exit 20
}
if (($Action -eq 'DLAA' -or $Action -eq 'FULL') -and -not (Test-FusionFixFirstRun $Game)) { Fail 'FusionFix is installed, but its first-run runtime file was not found. Launch GTA IV normally once with FusionFix installed, wait until the main menu appears, close the game, then run setup again from the same prerequisite folder.' }
if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before continuing.' }
if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before continuing.' }

$needsFoundationInputs = ($Action -eq 'DLAA') -or (($Action -eq 'FULL') -and -not (Test-DLAA $Game))
if ($needsFoundationInputs) {
    $env:GTAIV_SETUP_RESHADE = Require-InputFile $ReShadeSetup 'Official ReShade 6.8.0 Add-On installer'
    $lum = Resolve-LumenitePackage
    Assert-SHA256 $lum '572FEFB20D466AFE50998E16996B4833BEC675264485C99FE768A2337636E756' 'Pinned LumeniteFX ZIP'
    $env:GTAIV_SETUP_LUMENITE = $lum
}
if ($Action -eq 'FULL') {
    $gpuInfo = Get-GpuInfo
    $nr40DllHash = '4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05'
    $nr50DllHash = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'

    if ($NrPackage) {
        $ownNr = Require-InputFile $NrPackage 'Your Neural Rendering DLL'
        if ([IO.Path]::GetExtension($ownNr).ToLowerInvariant() -ne '.dll') {
            Fail 'I brought my own expects nvngx_dlssnr.dll, not a ZIP or another file type.'
        }
        if ($gpuInfo.Series -eq 40) {
            Assert-SHA256 $ownNr $nr40DllHash 'RTX 40 Neural Rendering DLL'
        } elseif ($gpuInfo.Series -eq 50) {
            Assert-SHA256 $ownNr $nr50DllHash 'RTX 50 Neural Rendering DLL'
            $sig = Get-AuthenticodeSignature -LiteralPath $ownNr
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA') {
                Fail 'RTX 50 Neural Rendering DLL is not the expected NVIDIA-signed runtime.'
            }
        } else {
            Fail "Full DLSS currently supports RTX 40/50. Detected: $($gpuInfo.Name)"
        }
        Write-Host 'Using user-provided Neural Rendering DLL.' -ForegroundColor Cyan
        $env:GTAIV_SETUP_NR_DLL = $ownNr
    }
    else {
        $nrZip = Resolve-AutoNrPackage
        if ($gpuInfo.Series -eq 40) {
            Assert-SHA256 $nrZip '46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F' 'RTX 40 DLSS NR ZIP'
        } elseif ($gpuInfo.Series -eq 50) {
            Assert-SHA256 $nrZip '388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC' 'RTX 50 DLSS NR ZIP'
        } else {
            Fail "Full DLSS currently supports RTX 40/50. Detected: $($gpuInfo.Name)"
        }
        $env:GTAIV_SETUP_NR_DLL = Resolve-NrPackage $nrZip
    }
}

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
    Write-Result 'Action completed successfully.'
}
catch {
    $message = $_.Exception.Message
    Write-Host ''
    Write-Host ('INSTALL FAILED: ' + $message) -ForegroundColor Red
    Write-Result $message
    exit 1
}
finally {
    if ($script:NrExtractTemp -and (Test-Path -LiteralPath $script:NrExtractTemp)) {
        Remove-Item -LiteralPath $script:NrExtractTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:AutoTemp -and (Test-Path -LiteralPath $script:AutoTemp)) {
        Remove-Item -LiteralPath $script:AutoTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
