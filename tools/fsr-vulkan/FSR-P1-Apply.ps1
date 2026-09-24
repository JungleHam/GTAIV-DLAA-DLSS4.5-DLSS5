param([string]$GameDir='')
$ErrorActionPreference='Stop'
$PackageDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidate=Join-Path $PackageDir 'dlss5-feed-fsr-p1.addon64'

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
    if(Test-Path -LiteralPath $Path){
        foreach($line in [IO.File]::ReadAllLines($Path)){[void]$lines.Add($line)}
    }
    $s=-1;$next=$lines.Count
    for($i=0;$i -lt $lines.Count;$i++){
        if($lines[$i].Trim() -ieq "[$Section]"){$s=$i;continue}
        if($s -ge 0 -and $i -gt $s -and $lines[$i].Trim().StartsWith('[')){$next=$i;break}
    }
    if($s -lt 0){
        if($lines.Count -and $lines[$lines.Count-1] -ne ''){$lines.Add('')}
        $lines.Add("[$Section]");$lines.Add("$Key=$Value")
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
$State=Join-Path $Trex '_FSR_P1_TEST_STATE'

if(-not(Test-Path -LiteralPath $Candidate)){throw "Test candidate missing: $Candidate"}
if(-not(Test-Path -LiteralPath $Live)){throw "Current feeder missing: $Live"}
if(-not(Test-Path -LiteralPath $Ini)){throw "Current settings missing: $Ini"}
if(Test-Path -LiteralPath $State){throw "A saved FSR test state already exists at $State. Run 2-RESTORE-BEFORE-FSR-P1.bat first; refusing to overwrite the clean backup."}

New-Item -ItemType Directory -Path $State | Out-Null
Copy-Item -LiteralPath $Live -Destination (Join-Path $State 'dlss5-feed.addon64') -Force
Copy-Item -LiteralPath $Ini -Destination (Join-Path $State 'm3k-nr.ini') -Force
if(Test-Path -LiteralPath $Log){
    Copy-Item -LiteralPath $Log -Destination (Join-Path $State 'dlss5-feed.log') -Force
}else{
    New-Item -ItemType File -Path (Join-Path $State 'LOG_WAS_MISSING') | Out-Null
}
@(
    "SavedUtc=$([DateTime]::UtcNow.ToString('o'))",
    "Game=$Game",
    "FeederSHA256=$((Get-FileHash -Algorithm SHA256 $Live).Hash)",
    "IniSHA256=$((Get-FileHash -Algorithm SHA256 $Ini).Hash)"
) | Set-Content -LiteralPath (Join-Path $State 'STATE.txt') -Encoding UTF8

try {
Copy-Item -LiteralPath $Candidate -Destination $Live -Force

# P1 uses the already-proven Quality render split only as temporary plumbing on this NVIDIA-hosted test.
# FSR output itself is isolated: once FSRProof=1, NGX/DLSS is forbidden from taking over a failed frame.
Set-Ini $Ini 'M3K' 'MasterEnabled' '1'
Set-Ini $Ini 'M3K' 'FSRProof' '1'
Set-Ini $Ini 'M3K' 'SRProof' '1'
Set-Ini $Ini 'M3K' 'SRProfile' '2'
Set-Ini $Ini 'M3K' 'Mode' '0'
Set-Ini $Ini 'M3K' 'Sharpness' '0.000'
Set-Ini $Ini 'M3K' 'TemporalJitter' '1'

Write-Host ''
Write-Host 'FSR P1 TEST APPLIED.'
Write-Host 'Saved the exact previous feeder, whole INI, and previous log under:'
Write-Host "  $State"
Write-Host ''
Write-Host 'Now launch GTA IV normally and play for 30-60 seconds with camera movement.'
Write-Host 'Then CLOSE GTA IV and run 2-RESTORE-BEFORE-FSR-P1.bat.'
Write-Host 'The restore BAT will also save the test log next to these BAT files.'
}
catch {
    Write-Host ''
    Write-Host 'APPLY encountered an error. Restoring the exact pre-test state automatically...'
    try {
        Copy-Item -LiteralPath (Join-Path $State 'dlss5-feed.addon64') -Destination $Live -Force
        Copy-Item -LiteralPath (Join-Path $State 'm3k-nr.ini') -Destination $Ini -Force
        $SavedLog=Join-Path $State 'dlss5-feed.log'
        if(Test-Path -LiteralPath $SavedLog){
            Copy-Item -LiteralPath $SavedLog -Destination $Log -Force
        }elseif(Test-Path -LiteralPath (Join-Path $State 'LOG_WAS_MISSING')){
            Remove-Item -LiteralPath $Log -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $State -Recurse -Force
        Write-Host 'Automatic rollback completed.'
    } catch {
        Write-Host 'Automatic rollback could not complete. DO NOT delete the saved state folder:'
        Write-Host "  $State"
    }
    throw
}
