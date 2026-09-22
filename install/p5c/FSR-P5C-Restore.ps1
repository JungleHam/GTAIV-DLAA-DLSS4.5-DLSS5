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
$ServerLog=Join-Path $Trex 'NvRemixBridge.log'
$State=Join-Path $Trex '_FSR_P5C_CAMERA_TEST_STATE'
if(-not(Test-Path $State)){throw "No saved FSR P5C state exists at $State"}

if(Test-Path $FeedLog){Copy-Item $FeedLog (Join-Path $PackageDir 'FSR-P5C-FEEDER-LOG.txt') -Force}
if(Test-Path $ServerLog){Copy-Item $ServerLog (Join-Path $PackageDir 'FSR-P5C-SERVER-LOG.txt') -Force}

foreach($name in @('NvRemixBridge.exe','dlss5-feed.addon64','m3k-nr.ini')){
    if(-not(Test-Path (Join-Path $State $name))){throw "Saved $name missing; state left untouched."}
}
Copy-Item (Join-Path $State 'NvRemixBridge.exe') $ServerLive -Force
Copy-Item (Join-Path $State 'dlss5-feed.addon64') $FeederLive -Force
Copy-Item (Join-Path $State 'm3k-nr.ini') $Ini -Force

if(Test-Path (Join-Path $State 'dlss5-feed.log')){Copy-Item (Join-Path $State 'dlss5-feed.log') $FeedLog -Force}
elseif(Test-Path (Join-Path $State 'FEED_LOG_WAS_MISSING')){Remove-Item $FeedLog -Force -ErrorAction SilentlyContinue}
if(Test-Path (Join-Path $State 'NvRemixBridge.log')){Copy-Item (Join-Path $State 'NvRemixBridge.log') $ServerLog -Force}
elseif(Test-Path (Join-Path $State 'SERVER_LOG_WAS_MISSING')){Remove-Item $ServerLog -Force -ErrorAction SilentlyContinue}

$stateText=Get-Content (Join-Path $State 'STATE.txt') -Raw
if($stateText -match 'ClientSHA256=([0-9A-Fa-f]{64})'){
    $expected=$Matches[1].ToUpperInvariant()
    $actual=(Get-FileHash -Algorithm SHA256 $ClientLive).Hash.ToUpperInvariant()
    if($actual -ne $expected){
        $nl=[Environment]::NewLine
        throw ("d3d9.dll changed during P5C unexpectedly. Saved test state is retained."+$nl+"Expected "+$expected+$nl+"Actual   "+$actual)
    }
}
Remove-Item $State -Recurse -Force

Write-Host ''
Write-Host 'PRE-P5C STATE RESTORED.'
Write-Host 'Send me FSR-P5C-SERVER-LOG.txt and FSR-P5C-FEEDER-LOG.txt from this folder.'
