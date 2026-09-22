param([string]$GameDir='')
$ErrorActionPreference='Stop'
$PackageDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgeCandidate=Join-Path $PackageDir 'd3d9-fsr-p5-camera-probe.dll'
$FeederCandidate=Join-Path $PackageDir 'dlss5-feed-fsr-p5.addon64'

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
function Set-Ini([string]$Path,[string]$Section,[string]$Key,[string]$Value){
    $lines=[Collections.Generic.List[string]]::new()
    if(Test-Path -LiteralPath $Path){foreach($line in [IO.File]::ReadAllLines($Path)){[void]$lines.Add($line)}}
    $s=-1;$next=$lines.Count
    for($i=0;$i -lt $lines.Count;$i++){
        if($lines[$i].Trim() -ieq "[$Section]"){$s=$i;continue}
        if($s -ge 0 -and $i -gt $s -and $lines[$i].Trim().StartsWith('[')){$next=$i;break}
    }
    if($s -lt 0){
        if($lines.Count -and $lines[$lines.Count-1] -ne ''){[void]$lines.Add('')}
        [void]$lines.Add("[$Section]");[void]$lines.Add("$Key=$Value")
    }else{
        $done=$false
        for($i=$s+1;$i -lt $next;$i++){
            if($lines[$i] -match ('^\s*'+[regex]::Escape($Key)+'\s*=')){$lines[$i]="$Key=$Value";$done=$true;break}
        }
        if(-not $done){$lines.Insert($next,"$Key=$Value")}
    }
    [IO.File]::WriteAllLines($Path,$lines,[Text.UTF8Encoding]::new($false))
}

Assert-Stopped
$Game=Resolve-Game $GameDir
$Trex=Join-Path $Game '.trex'
$BridgeLive=Join-Path $Game 'd3d9.dll'
$FeederLive=Join-Path $Trex 'dlss5-feed.addon64'
$Ini=Join-Path $Trex 'm3k-nr.ini'
$FeedLog=Join-Path $Trex 'dlss5-feed.log'
$BridgeLog=Join-Path $Game 'd3d9.log'
$State=Join-Path $Trex '_FSR_P5_CAMERA_TEST_STATE'

foreach($p in @($BridgeCandidate,$FeederCandidate,$BridgeLive,$FeederLive,$Ini)){
    if(-not(Test-Path -LiteralPath $p)){throw "Required file missing: $p"}
}
if(Test-Path -LiteralPath $State){throw "A saved FSR P5 state already exists at $State. Run 2-RESTORE-BEFORE-FSR-P5.bat first."}

New-Item -ItemType Directory -Path $State | Out-Null
Copy-Item $BridgeLive (Join-Path $State 'd3d9.dll') -Force
Copy-Item $FeederLive (Join-Path $State 'dlss5-feed.addon64') -Force
Copy-Item $Ini (Join-Path $State 'm3k-nr.ini') -Force
if(Test-Path $FeedLog){Copy-Item $FeedLog (Join-Path $State 'dlss5-feed.log') -Force}else{New-Item -ItemType File (Join-Path $State 'FEED_LOG_WAS_MISSING')|Out-Null}
if(Test-Path $BridgeLog){Copy-Item $BridgeLog (Join-Path $State 'd3d9.log') -Force}else{New-Item -ItemType File (Join-Path $State 'BRIDGE_LOG_WAS_MISSING')|Out-Null}

try{
    Copy-Item $BridgeCandidate $BridgeLive -Force
    Copy-Item $FeederCandidate $FeederLive -Force
    Set-Ini $Ini 'M3K' 'MasterEnabled' '1'
    Set-Ini $Ini 'M3K' 'FSRProof' '1'
    Set-Ini $Ini 'M3K' 'FSRScalePermille' '667'
    Set-Ini $Ini 'M3K' 'SRProof' '0'
    Set-Ini $Ini 'M3K' 'TemporalJitter' '1'
    Set-Ini $Ini 'M3K' 'StartupPrime' '0'
    Remove-Item $FeedLog,$BridgeLog -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'FSR P5 CAMERA PROBE APPLIED.'
    Write-Host 'Rendering behavior is the validated P4A path; this bridge adds read-only camera telemetry.'
    Write-Host ''
    Write-Host 'Launch GTA IV, reach normal outdoor gameplay, pan the camera and drive for 20-30 seconds.'
    Write-Host 'Then close GTA IV and run 2-RESTORE-BEFORE-FSR-P5.bat.'
}catch{
    try{
        Copy-Item (Join-Path $State 'd3d9.dll') $BridgeLive -Force
        Copy-Item (Join-Path $State 'dlss5-feed.addon64') $FeederLive -Force
        Copy-Item (Join-Path $State 'm3k-nr.ini') $Ini -Force
        if(Test-Path (Join-Path $State 'dlss5-feed.log')){Copy-Item (Join-Path $State 'dlss5-feed.log') $FeedLog -Force}else{Remove-Item $FeedLog -Force -ErrorAction SilentlyContinue}
        if(Test-Path (Join-Path $State 'd3d9.log')){Copy-Item (Join-Path $State 'd3d9.log') $BridgeLog -Force}else{Remove-Item $BridgeLog -Force -ErrorAction SilentlyContinue}
        Remove-Item $State -Recurse -Force
        Write-Host 'Automatic rollback completed.'
    }catch{Write-Host "Rollback incomplete. Keep saved state: $State"}
    throw
}
