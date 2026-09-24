param([string]$GameDir='')
$ErrorActionPreference='Stop'
$PackageDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$ClientCandidate=Join-Path $PackageDir 'd3d9-fsr-p5b-camera-probe.dll'
$ServerCandidate=Join-Path $PackageDir 'NvRemixBridge-fsr-p5b.exe'
$FeederCandidate=Join-Path $PackageDir 'dlss5-feed-fsr-p5b.addon64'

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
$ClientLive=Join-Path $Game 'd3d9.dll'
$ServerLive=Join-Path $Trex 'NvRemixBridge.exe'
$FeederLive=Join-Path $Trex 'dlss5-feed.addon64'
$Ini=Join-Path $Trex 'm3k-nr.ini'
$FeedLog=Join-Path $Trex 'dlss5-feed.log'
$BridgeLog=Join-Path $Game 'd3d9.log'
$ServerLog=Join-Path $Trex 'NvRemixBridge.log'
$State=Join-Path $Trex '_FSR_P5B_CAMERA_TEST_STATE'

foreach($p in @($ClientCandidate,$ServerCandidate,$FeederCandidate,$ClientLive,$ServerLive,$FeederLive,$Ini)){
    if(-not(Test-Path -LiteralPath $p)){throw "Required file missing: $p"}
}
if(Test-Path -LiteralPath $State){throw "A saved FSR P5B state already exists at $State. Run 2-RESTORE-BEFORE-FSR-P5B.bat first."}

New-Item -ItemType Directory -Path $State | Out-Null
Copy-Item $ClientLive (Join-Path $State 'd3d9.dll') -Force
Copy-Item $ServerLive (Join-Path $State 'NvRemixBridge.exe') -Force
Copy-Item $FeederLive (Join-Path $State 'dlss5-feed.addon64') -Force
Copy-Item $Ini (Join-Path $State 'm3k-nr.ini') -Force
foreach($pair in @(
    @($FeedLog,'dlss5-feed.log','FEED_LOG_WAS_MISSING'),
    @($BridgeLog,'d3d9.log','BRIDGE_LOG_WAS_MISSING'),
    @($ServerLog,'NvRemixBridge.log','SERVER_LOG_WAS_MISSING')
)){
    if(Test-Path $pair[0]){Copy-Item $pair[0] (Join-Path $State $pair[1]) -Force}
    else{New-Item -ItemType File (Join-Path $State $pair[2])|Out-Null}
}
@(
    "SavedUtc=$([DateTime]::UtcNow.ToString('o'))",
    "ClientSHA256=$((Get-FileHash -Algorithm SHA256 $ClientLive).Hash)",
    "ServerSHA256=$((Get-FileHash -Algorithm SHA256 $ServerLive).Hash)",
    "FeederSHA256=$((Get-FileHash -Algorithm SHA256 $FeederLive).Hash)",
    "IniSHA256=$((Get-FileHash -Algorithm SHA256 $Ini).Hash)"
)|Set-Content (Join-Path $State 'STATE.txt') -Encoding UTF8

try{
    Copy-Item $ClientCandidate $ClientLive -Force
    Copy-Item $ServerCandidate $ServerLive -Force
    Copy-Item $FeederCandidate $FeederLive -Force

    # Reproduce the exact known-good P4A runtime state, explicitly.
    Set-Ini $Ini 'M3K' 'MasterEnabled' '1'
    Set-Ini $Ini 'M3K' 'FSRProof' '1'
    Set-Ini $Ini 'M3K' 'FSRScalePermille' '667'
    Set-Ini $Ini 'M3K' 'SRProof' '0'
    Set-Ini $Ini 'M3K' 'SRProfile' '2'
    Set-Ini $Ini 'M3K' 'Mode' '0'
    Set-Ini $Ini 'M3K' 'Sharpness' '0.000'
    Set-Ini $Ini 'M3K' 'AutoResizeWindow' '1'
    Set-Ini $Ini 'M3K' 'VirtualizeGameClient' '1'
    Set-Ini $Ini 'M3K' 'TemporalJitter' '1'
    Set-Ini $Ini 'M3K' 'JitterMode' '0'
    Set-Ini $Ini 'M3K' 'StartupPrime' '0'

    Remove-Item $FeedLog,$BridgeLog,$ServerLog -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'FSR P5B CAMERA PROBE APPLIED.'
    Write-Host 'This uses a matched d3d9.dll + NvRemixBridge.exe pair and explicitly restores the known-good P4A UI/jitter settings.'
    Write-Host ''
    Write-Host 'Launch GTA IV, confirm menus/HUD are normal, then reach outdoor gameplay and pan/drive for 20-30 seconds.'
    Write-Host 'Close GTA IV and run 2-RESTORE-BEFORE-FSR-P5B.bat.'
}catch{
    try{
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
        Write-Host 'Automatic rollback completed.'
    }catch{Write-Host "Rollback incomplete. Keep saved state: $State"}
    throw
}
