param([string]$GameDir='')
$ErrorActionPreference='Stop'
$PackageDir=Split-Path -Parent $MyInvocation.MyCommand.Path
function Resolve-Game([string]$Requested){
    if($Requested -and (Test-Path -LiteralPath (Join-Path $Requested 'GTAIV.exe'))){return (Resolve-Path $Requested).Path}
    $cwd=(Get-Location).Path
    if(Test-Path -LiteralPath (Join-Path $cwd 'GTAIV.exe')){return $cwd}
    $p=Read-Host 'Enter GTA IV folder containing GTAIV.exe'
    if(-not $p -or -not(Test-Path -LiteralPath (Join-Path $p 'GTAIV.exe'))){throw 'GTAIV.exe not found.'}
    return (Resolve-Path $p).Path
}
function Assert-Stopped {
    if(Get-Process GTAIV -ErrorAction SilentlyContinue){throw 'Close GTA IV first.'}
    if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){throw 'Close NvRemixBridge.exe first.'}
}
Assert-Stopped
$Game=Resolve-Game $GameDir
$Trex=Join-Path $Game '.trex'
$Live=Join-Path $Trex 'dlss5-feed.addon64'
$Ini=Join-Path $Trex 'm3k-nr.ini'
$Log=Join-Path $Trex 'dlss5-feed.log'
$State=Join-Path $Trex '_FSR_P4A_TEST_STATE'
if(-not(Test-Path -LiteralPath $State)){throw "No saved FSR P4A state exists at $State"}

if(Test-Path -LiteralPath $Log){Copy-Item -LiteralPath $Log -Destination (Join-Path $PackageDir 'FSR-P4A-TEST-LOG.txt') -Force}

foreach($name in @('dlss5-feed.addon64','m3k-nr.ini')){
    if(-not(Test-Path -LiteralPath (Join-Path $State $name))){throw "Saved $name is missing; state folder left untouched."}
}
Copy-Item -LiteralPath (Join-Path $State 'dlss5-feed.addon64') -Destination $Live -Force
Copy-Item -LiteralPath (Join-Path $State 'm3k-nr.ini') -Destination $Ini -Force
$SavedLog=Join-Path $State 'dlss5-feed.log'
if(Test-Path -LiteralPath $SavedLog){Copy-Item -LiteralPath $SavedLog -Destination $Log -Force}
elseif(Test-Path -LiteralPath (Join-Path $State 'LOG_WAS_MISSING')){Remove-Item -LiteralPath $Log -Force -ErrorAction SilentlyContinue}
Remove-Item -LiteralPath $State -Recurse -Force

Write-Host ''
Write-Host 'PRE-P4A STATE RESTORED.'
Write-Host 'Your exact previous feeder, INI and previous log are back. d3d9.dll was never touched.'
if(Test-Path -LiteralPath (Join-Path $PackageDir 'FSR-P4A-TEST-LOG.txt')){
    Write-Host 'P4A test log saved here:'
    Write-Host "  $(Join-Path $PackageDir 'FSR-P4A-TEST-LOG.txt')"
    Write-Host 'Send me that file.'
}
