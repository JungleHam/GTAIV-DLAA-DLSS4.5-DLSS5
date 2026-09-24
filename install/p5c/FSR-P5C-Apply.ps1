param([string]$GameDir='')
$ErrorActionPreference='Stop'
$PackageDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$ServerCandidate=Join-Path $PackageDir 'NvRemixBridge-fsr-p5c.exe'
$FeederCandidate=Join-Path $PackageDir 'dlss5-feed-fsr-p5c.addon64'

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
$ServerLog=Join-Path $Game 'rtx-remix\logs\bridge64.log'
$State=Join-Path $Trex '_FSR_P5C_CAMERA_TEST_STATE'

foreach($p in @($ServerCandidate,$FeederCandidate,$ClientLive,$ServerLive,$FeederLive,$Ini)){
    if(-not(Test-Path -LiteralPath $p)){throw "Required file missing: $p"}
}
if(Test-Path -LiteralPath $State){throw "A saved FSR P5C state already exists at $State. Run 2-RESTORE-BEFORE-FSR-P5C.bat first."}

New-Item -ItemType Directory -Path $State | Out-Null
Copy-Item $ServerLive (Join-Path $State 'NvRemixBridge.exe') -Force
Copy-Item $FeederLive (Join-Path $State 'dlss5-feed.addon64') -Force
Copy-Item $Ini (Join-Path $State 'm3k-nr.ini') -Force
if(Test-Path $FeedLog){Copy-Item $FeedLog (Join-Path $State 'dlss5-feed.log') -Force}else{New-Item -ItemType File (Join-Path $State 'FEED_LOG_WAS_MISSING')|Out-Null}
if(Test-Path $ServerLog){Copy-Item $ServerLog (Join-Path $State 'NvRemixBridge.log') -Force}else{New-Item -ItemType File (Join-Path $State 'SERVER_LOG_WAS_MISSING')|Out-Null}

$ClientHashBefore=(Get-FileHash -Algorithm SHA256 $ClientLive).Hash.ToUpperInvariant()
@(
    "SavedUtc=$([DateTime]::UtcNow.ToString('o'))",
    "ProductionClientUNTOUCHED=$ClientLive",
    "ClientSHA256=$ClientHashBefore",
    "ServerSHA256=$((Get-FileHash -Algorithm SHA256 $ServerLive).Hash)",
    "FeederSHA256=$((Get-FileHash -Algorithm SHA256 $FeederLive).Hash)",
    "IniSHA256=$((Get-FileHash -Algorithm SHA256 $Ini).Hash)"
)|Set-Content (Join-Path $State 'STATE.txt') -Encoding UTF8

try{
    Copy-Item $ServerCandidate $ServerLive -Force
    Copy-Item $FeederCandidate $FeederLive -Force

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

    $ClientHashAfter=(Get-FileHash -Algorithm SHA256 $ClientLive).Hash.ToUpperInvariant()
    if($ClientHashAfter -ne $ClientHashBefore){throw 'Safety check failed: d3d9.dll changed even though P5C must never touch it.'}

    Remove-Item $FeedLog,$ServerLog -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'FSR P5C SERVER-ONLY CAMERA PROBE APPLIED.'
    Write-Host 'd3d9.dll was NOT changed. Its SHA256 is unchanged:'
    Write-Host "  $ClientHashAfter"
    Write-Host ''
    Write-Host 'First check the main menu/HUD. They should look exactly like the successful P4A test.'
    Write-Host 'Then reach outdoor gameplay, pan the camera and drive for about 20-30 seconds.'
    Write-Host 'Close GTA IV and run 2-RESTORE-BEFORE-FSR-P5C.bat.'
}catch{
    try{
        Copy-Item (Join-Path $State 'NvRemixBridge.exe') $ServerLive -Force
        Copy-Item (Join-Path $State 'dlss5-feed.addon64') $FeederLive -Force
        Copy-Item (Join-Path $State 'm3k-nr.ini') $Ini -Force
        if(Test-Path (Join-Path $State 'dlss5-feed.log')){Copy-Item (Join-Path $State 'dlss5-feed.log') $FeedLog -Force}
        elseif(Test-Path (Join-Path $State 'FEED_LOG_WAS_MISSING')){Remove-Item $FeedLog -Force -ErrorAction SilentlyContinue}
        if(Test-Path (Join-Path $State 'NvRemixBridge.log')){Copy-Item (Join-Path $State 'NvRemixBridge.log') $ServerLog -Force}
        elseif(Test-Path (Join-Path $State 'SERVER_LOG_WAS_MISSING')){Remove-Item $ServerLog -Force -ErrorAction SilentlyContinue}
        Remove-Item $State -Recurse -Force
        Write-Host 'Automatic rollback completed.'
    }catch{Write-Host "Rollback incomplete. Keep saved state: $State"}
    throw
}
