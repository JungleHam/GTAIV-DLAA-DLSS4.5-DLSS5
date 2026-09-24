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
if(Get-Process GTAIV -ErrorAction SilentlyContinue){throw 'Close GTA IV first.'}
if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){throw 'Close NvRemixBridge.exe first.'}
$Game=Resolve-Game $GameDir
$Trex=Join-Path $Game '.trex'
$Live=Join-Path $Trex 'dlss5-feed.addon64'
$Ini=Join-Path $Trex 'm3k-nr.ini'
$Log=Join-Path $Trex 'dlss5-feed.log'
$State=Join-Path $Trex '_FSR_P9C_ALL_BACKENDS_TEST_STATE'
if(-not(Test-Path $State)){throw "No saved P9C state exists at $State"}

if(Test-Path $Log){Copy-Item $Log (Join-Path $PackageDir 'FSR-P9C-TEST-LOG.txt') -Force}
foreach($name in @('dlss5-feed.addon64','m3k-nr.ini')){
    if(-not(Test-Path (Join-Path $State $name))){throw "Saved $name missing; state left untouched."}
}
Copy-Item (Join-Path $State 'dlss5-feed.addon64') $Live -Force
Copy-Item (Join-Path $State 'm3k-nr.ini') $Ini -Force
if(Test-Path (Join-Path $State 'dlss5-feed.log')){Copy-Item (Join-Path $State 'dlss5-feed.log') $Log -Force}
elseif(Test-Path (Join-Path $State 'LOG_WAS_MISSING')){Remove-Item $Log -Force -ErrorAction SilentlyContinue}
Remove-Item $State -Recurse -Force

Write-Host ''
Write-Host 'PRE-P9C STATE RESTORED.'
if(Test-Path (Join-Path $PackageDir 'FSR-P9C-TEST-LOG.txt')){Write-Host 'Send me FSR-P9C-TEST-LOG.txt from this folder.'}
