param([string]$GameDir='')
$ErrorActionPreference='Stop'
$PackageDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidate=Join-Path $PackageDir 'dlss5-feed-fsr-p9c.addon64'

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
$Live=Join-Path $Trex 'dlss5-feed.addon64'
$Ini=Join-Path $Trex 'm3k-nr.ini'
$Log=Join-Path $Trex 'dlss5-feed.log'
$State=Join-Path $Trex '_FSR_P9C_ALL_BACKENDS_TEST_STATE'
if(-not(Test-Path $Candidate)){throw "P9C candidate missing: $Candidate"}
foreach($p in @($Live,$Ini)){if(-not(Test-Path $p)){throw "Current install file missing: $p"}}
if(Test-Path $State){throw "A saved P9C state already exists at $State. Run 2-RESTORE-BEFORE-P9C.bat first."}

New-Item -ItemType Directory -Path $State|Out-Null
Copy-Item $Live (Join-Path $State 'dlss5-feed.addon64') -Force
Copy-Item $Ini (Join-Path $State 'm3k-nr.ini') -Force
if(Test-Path $Log){Copy-Item $Log (Join-Path $State 'dlss5-feed.log') -Force}else{New-Item -ItemType File (Join-Path $State 'LOG_WAS_MISSING')|Out-Null}

try{
    Copy-Item $Candidate $Live -Force
    Set-Ini $Ini 'M3K' 'ScalingTechnology' '0'
    Set-Ini $Ini 'M3K' 'FSRProof' '0'
    Set-Ini $Ini 'M3K' 'MasterEnabled' '1'
    Set-Ini $Ini 'M3K' 'FSRScalePermille' '667'
    Set-Ini $Ini 'M3K' 'FSRSharpness' '0.250'
    Set-Ini $Ini 'M3K' 'SRProof' '0'
    Set-Ini $Ini 'M3K' 'SRProfile' '2'
    Set-Ini $Ini 'M3K' 'LastSRProfile' '2'
    Set-Ini $Ini 'M3K' 'LastNRMode' '0'
    Set-Ini $Ini 'M3K' 'Mode' '0'
    Set-Ini $Ini 'M3K' 'Sharpness' '0.000'
    Set-Ini $Ini 'M3K' 'AutoResizeWindow' '1'
    Set-Ini $Ini 'M3K' 'VirtualizeGameClient' '1'
    Set-Ini $Ini 'M3K' 'TemporalJitter' '1'
    Set-Ini $Ini 'M3K' 'JitterMode' '0'
    Set-Ini $Ini 'M3K' 'StartupPrime' '0'
    Set-Ini $Ini 'M3K' 'FSRCameraNear' '0.05'
    Set-Ini $Ini 'M3K' 'FSRCameraFar' '1500'
    Set-Ini $Ini 'M3K' 'FSRCameraFovYDegrees' '45'
    Remove-Item $Log -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'P9C FULL LIVE OFF / NVIDIA / AMD TEST APPLIED.'
    Write-Host 'Initial backend: Off. NVIDIA=Quality; AMD=66.7% + RCAS 0.25.'
    Write-Host 'd3d9.dll and NvRemixBridge.exe were NOT changed.'
    Write-Host ''
    Write-Host 'In GTA IV use Home -> Add-ons -> DLSS 5 Feed -> GTA IV Reconstruction.'
    Write-Host 'Switch one step at a time. P9C also verifies a NVIDIA->Off request cannot be consumed by the NVIDIA SR finalizer.'
    Write-Host 'Test all three backends. Direct NVIDIA <-> AMD must pass through an automatic Off/raw midpoint.'
    Write-Host 'If anything looks wrong or GTA crashes, stop the test and restore.'
}catch{
    try{
        Copy-Item (Join-Path $State 'dlss5-feed.addon64') $Live -Force
        Copy-Item (Join-Path $State 'm3k-nr.ini') $Ini -Force
        if(Test-Path (Join-Path $State 'dlss5-feed.log')){Copy-Item (Join-Path $State 'dlss5-feed.log') $Log -Force}
        elseif(Test-Path (Join-Path $State 'LOG_WAS_MISSING')){Remove-Item $Log -Force -ErrorAction SilentlyContinue}
        Remove-Item $State -Recurse -Force
        Write-Host 'Automatic rollback completed.'
    }catch{Write-Host "Rollback incomplete. Keep saved state: $State"}
    throw
}
