param([string]$GameDir='')
$ErrorActionPreference='Stop'
$PackageDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgeCandidate=Join-Path $PackageDir 'd3d9-fsr-p4.dll'
$FeederCandidate=Join-Path $PackageDir 'dlss5-feed-fsr-p4.addon64'

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
$Log=Join-Path $Trex 'dlss5-feed.log'
$State=Join-Path $Trex '_FSR_P4_TEST_STATE'

foreach($p in @($BridgeCandidate,$FeederCandidate)){if(-not(Test-Path -LiteralPath $p)){throw "Test candidate missing: $p"}}
foreach($p in @($BridgeLive,$FeederLive,$Ini)){if(-not(Test-Path -LiteralPath $p)){throw "Current install file missing: $p"}}
if(Test-Path -LiteralPath $State){throw "A saved FSR P4 state already exists at $State. Run 2-RESTORE-BEFORE-FSR-P4.bat first; refusing to overwrite it."}

New-Item -ItemType Directory -Path $State | Out-Null
Copy-Item -LiteralPath $BridgeLive -Destination (Join-Path $State 'd3d9.dll') -Force
Copy-Item -LiteralPath $FeederLive -Destination (Join-Path $State 'dlss5-feed.addon64') -Force
Copy-Item -LiteralPath $Ini -Destination (Join-Path $State 'm3k-nr.ini') -Force
if(Test-Path -LiteralPath $Log){Copy-Item -LiteralPath $Log -Destination (Join-Path $State 'dlss5-feed.log') -Force}
else{New-Item -ItemType File -Path (Join-Path $State 'LOG_WAS_MISSING') | Out-Null}
@(
    "SavedUtc=$([DateTime]::UtcNow.ToString('o'))",
    "Game=$Game",
    "BridgeSHA256=$((Get-FileHash -Algorithm SHA256 $BridgeLive).Hash)",
    "FeederSHA256=$((Get-FileHash -Algorithm SHA256 $FeederLive).Hash)",
    "IniSHA256=$((Get-FileHash -Algorithm SHA256 $Ini).Hash)"
) | Set-Content -LiteralPath (Join-Path $State 'STATE.txt') -Encoding UTF8

try{
    Copy-Item -LiteralPath $BridgeCandidate -Destination $BridgeLive -Force
    Copy-Item -LiteralPath $FeederCandidate -Destination $FeederLive -Force
    Set-Ini $Ini 'M3K' 'MasterEnabled' '1'
    Set-Ini $Ini 'M3K' 'FSRProof' '1'
    Set-Ini $Ini 'M3K' 'FSRScalePermille' '667'
    Set-Ini $Ini 'M3K' 'SRProof' '0'
    Set-Ini $Ini 'M3K' 'SRProfile' '2'
    Set-Ini $Ini 'M3K' 'Mode' '0'
    Set-Ini $Ini 'M3K' 'Sharpness' '0.000'
    Set-Ini $Ini 'M3K' 'TemporalJitter' '1'
    Set-Ini $Ini 'M3K' 'JitterMode' '0'
    Set-Ini $Ini 'M3K' 'StartupPrime' '0'

    Write-Host ''
    Write-Host 'FSR P4 TEMPORAL TEST APPLIED.'
    Write-Host 'This test temporarily replaced BOTH the b-bridge d3d9.dll and the FSR feeder.'
    Write-Host 'DLSS behavior inside the P4 bridge remains on its old sequence; only FSRProof=1 selects AMD jitter.'
    Write-Host ''
    Write-Host 'Launch GTA IV, reach gameplay, then slowly pan, fast-pan, and drive for about 60 seconds.'
    Write-Host 'Close GTA IV and run 2-RESTORE-BEFORE-FSR-P4.bat.'
}
catch{
    Write-Host ''
    Write-Host 'APPLY encountered an error. Restoring the exact pre-test state automatically...'
    try{
        Copy-Item -LiteralPath (Join-Path $State 'd3d9.dll') -Destination $BridgeLive -Force
        Copy-Item -LiteralPath (Join-Path $State 'dlss5-feed.addon64') -Destination $FeederLive -Force
        Copy-Item -LiteralPath (Join-Path $State 'm3k-nr.ini') -Destination $Ini -Force
        $SavedLog=Join-Path $State 'dlss5-feed.log'
        if(Test-Path -LiteralPath $SavedLog){Copy-Item -LiteralPath $SavedLog -Destination $Log -Force}
        elseif(Test-Path -LiteralPath (Join-Path $State 'LOG_WAS_MISSING')){Remove-Item -LiteralPath $Log -Force -ErrorAction SilentlyContinue}
        Remove-Item -LiteralPath $State -Recurse -Force
        Write-Host 'Automatic rollback completed.'
    }catch{
        Write-Host 'Automatic rollback could not complete. DO NOT delete the saved state folder:'
        Write-Host "  $State"
    }
    throw
}
