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
$ClientLive=Join-Path $Game 'd3d9.dll'
$ServerLive=Join-Path $Trex 'NvRemixBridge.exe'
$FeederLive=Join-Path $Trex 'dlss5-feed.addon64'
$Ini=Join-Path $Trex 'm3k-nr.ini'
$FeedLog=Join-Path $Trex 'dlss5-feed.log'
$BridgeLog=Join-Path $Game 'd3d9.log'
$ServerLog=Join-Path $Trex 'NvRemixBridge.log'
$State=Join-Path $Trex '_FSR_P5B_CAMERA_TEST_STATE'
if(-not(Test-Path $State)){throw "No saved FSR P5B state exists at $State"}

if(Test-Path $FeedLog){Copy-Item $FeedLog (Join-Path $PackageDir 'FSR-P5B-FEEDER-LOG.txt') -Force}
if(Test-Path $BridgeLog){Copy-Item $BridgeLog (Join-Path $PackageDir 'FSR-P5B-D3D9-LOG.txt') -Force}
if(Test-Path $ServerLog){Copy-Item $ServerLog (Join-Path $PackageDir 'FSR-P5B-SERVER-LOG.txt') -Force}

foreach($name in @('d3d9.dll','NvRemixBridge.exe','dlss5-feed.addon64','m3k-nr.ini')){
    if(-not(Test-Path (Join-Path $State $name))){throw "Saved $name missing; state left untouched."}
}
Copy-Item (Join-Path $State 'd3d9.dll') $ClientLive -Force
Copy-Item (Join-Path $State 'NvRemixBridge.exe') $ServerLive -Force
Copy-Item (Join-Path $State 'dlss5-feed.addon64') $FeederLive -Force
Copy-Item (Join-Path $State 'm3k-nr.ini') $Ini -Force

foreach($pair in @(
    @('dlss5-feed.log',$FeedLog,'FEED_LOG_WAS_MISSING'),
    @('d3d9.log',$BridgeLog,'BRIDGE_LOG_WAS_MISSING'),
    @('NvRemixBridge.log',$ServerLog,'SERVER_LOG_WAS_MISSING')
)){
    $saved=Join-Path $State $pair[0]
    if(Test-Path $saved){Copy-Item $saved $pair[1] -Force}
    elseif(Test-Path (Join-Path $State $pair[2])){Remove-Item $pair[1] -Force -ErrorAction SilentlyContinue}
}
Remove-Item $State -Recurse -Force

Write-Host ''
Write-Host 'PRE-P5B STATE RESTORED.'
Write-Host 'Send me FSR-P5B-D3D9-LOG.txt and FSR-P5B-FEEDER-LOG.txt. SERVER log is optional unless there is a bridge problem.'
