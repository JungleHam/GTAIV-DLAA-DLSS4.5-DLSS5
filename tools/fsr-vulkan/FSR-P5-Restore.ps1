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
$BridgeLive=Join-Path $Game 'd3d9.dll'
$FeederLive=Join-Path $Trex 'dlss5-feed.addon64'
$Ini=Join-Path $Trex 'm3k-nr.ini'
$FeedLog=Join-Path $Trex 'dlss5-feed.log'
$BridgeLog=Join-Path $Game 'd3d9.log'
$State=Join-Path $Trex '_FSR_P5_CAMERA_TEST_STATE'
if(-not(Test-Path $State)){throw "No saved FSR P5 state exists at $State"}

if(Test-Path $FeedLog){Copy-Item $FeedLog (Join-Path $PackageDir 'FSR-P5-FEEDER-LOG.txt') -Force}
if(Test-Path $BridgeLog){Copy-Item $BridgeLog (Join-Path $PackageDir 'FSR-P5-D3D9-LOG.txt') -Force}

foreach($name in @('d3d9.dll','dlss5-feed.addon64','m3k-nr.ini')){
    if(-not(Test-Path (Join-Path $State $name))){throw "Saved $name missing; state left untouched."}
}
Copy-Item (Join-Path $State 'd3d9.dll') $BridgeLive -Force
Copy-Item (Join-Path $State 'dlss5-feed.addon64') $FeederLive -Force
Copy-Item (Join-Path $State 'm3k-nr.ini') $Ini -Force

if(Test-Path (Join-Path $State 'dlss5-feed.log')){Copy-Item (Join-Path $State 'dlss5-feed.log') $FeedLog -Force}
elseif(Test-Path (Join-Path $State 'FEED_LOG_WAS_MISSING')){Remove-Item $FeedLog -Force -ErrorAction SilentlyContinue}
if(Test-Path (Join-Path $State 'd3d9.log')){Copy-Item (Join-Path $State 'd3d9.log') $BridgeLog -Force}
elseif(Test-Path (Join-Path $State 'BRIDGE_LOG_WAS_MISSING')){Remove-Item $BridgeLog -Force -ErrorAction SilentlyContinue}
Remove-Item $State -Recurse -Force

Write-Host ''
Write-Host 'PRE-P5 STATE RESTORED.'
Write-Host 'Send me FSR-P5-D3D9-LOG.txt and FSR-P5-FEEDER-LOG.txt from this folder.'
