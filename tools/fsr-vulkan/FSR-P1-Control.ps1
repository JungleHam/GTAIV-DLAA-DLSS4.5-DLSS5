param(
    [ValidateSet('enable','disable','restore','status','log')]
    [string]$Action = 'status',
    [string]$GameDir = ''
)

$ErrorActionPreference='Stop'
$PackageDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidate=Join-Path $PackageDir 'dlss5-feed-fsr-p1.addon64'

function Resolve-GameDir {
    param([string]$Requested)
    if($Requested -and (Test-Path -LiteralPath (Join-Path $Requested 'GTAIV.exe'))){ return (Resolve-Path $Requested).Path }
    $cwd=(Get-Location).Path
    if(Test-Path -LiteralPath (Join-Path $cwd 'GTAIV.exe')){ return $cwd }
    $p=Read-Host 'Enter GTA IV folder containing GTAIV.exe'
    if(-not $p -or -not(Test-Path -LiteralPath (Join-Path $p 'GTAIV.exe'))){ throw 'GTAIV.exe not found.' }
    return (Resolve-Path $p).Path
}

function Assert-Stopped {
    if(Get-Process GTAIV -ErrorAction SilentlyContinue){ throw 'Close GTA IV first.' }
    if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){ throw 'Close NvRemixBridge.exe first.' }
}

function Set-IniValue {
    param([string]$Path,[string]$Section,[string]$Key,[string]$Value)
    $lines = if(Test-Path -LiteralPath $Path){ [Collections.Generic.List[string]](Get-Content -LiteralPath $Path) } else { [Collections.Generic.List[string]]::new() }
    $sectionLine=-1; $nextSection=$lines.Count
    for($i=0;$i -lt $lines.Count;$i++){
        if($lines[$i].Trim() -ieq "[$Section]"){ $sectionLine=$i; continue }
        if($sectionLine -ge 0 -and $i -gt $sectionLine -and $lines[$i].Trim().StartsWith('[')){ $nextSection=$i; break }
    }
    if($sectionLine -lt 0){
        if($lines.Count -gt 0 -and $lines[$lines.Count-1] -ne ''){ $lines.Add('') }
        $lines.Add("[$Section]"); $lines.Add("$Key=$Value")
    } else {
        $found=$false
        for($i=$sectionLine+1;$i -lt $nextSection;$i++){
            if($lines[$i] -match ('^\s*'+[regex]::Escape($Key)+'\s*=')){
                $lines[$i]="$Key=$Value"; $found=$true; break
            }
        }
        if(-not $found){ $lines.Insert($nextSection,"$Key=$Value") }
    }
    [IO.File]::WriteAllLines($Path,$lines,[Text.UTF8Encoding]::new($false))
}

$Game=Resolve-GameDir $GameDir
$Trex=Join-Path $Game '.trex'
$Live=Join-Path $Trex 'dlss5-feed.addon64'
$Backup=Join-Path $Trex 'dlss5-feed.before-fsr-p1.addon64'
$Ini=Join-Path $Trex 'm3k-nr.ini'
$Log=Join-Path $Trex 'dlss5-feed.log'

if(-not(Test-Path -LiteralPath $Trex)){ throw '.trex folder not found. Install the current DLSS Full baseline first.' }
if(-not(Test-Path -LiteralPath $Ini)){ throw '.trex\m3k-nr.ini not found. Install the current DLSS Full baseline first.' }

switch($Action){
    'enable' {
        Assert-Stopped
        if(-not(Test-Path -LiteralPath $Candidate)){ throw "Candidate missing next to controller: $Candidate" }
        if(-not(Test-Path -LiteralPath $Live)){ throw "Production feeder missing: $Live" }
        if(-not(Test-Path -LiteralPath $Backup)){
            Copy-Item -LiteralPath $Live -Destination $Backup -Force
            Write-Host "Backed up production feeder -> $Backup"
        } else {
            Write-Host 'Existing FSR-P1 feeder backup kept.'
        }
        Copy-Item -LiteralPath $Candidate -Destination $Live -Force
        Set-IniValue $Ini 'M3K' 'FSRProof' '1'
        Write-Host ''
        Write-Host 'FSR P1 ENABLED.'
        Write-Host 'Launch GTA IV normally. After reaching gameplay, run:'
        Write-Host '  FSR-P1-Control.bat log'
    }
    'disable' {
        Assert-Stopped
        Set-IniValue $Ini 'M3K' 'FSRProof' '0'
        Write-Host 'FSR proof disabled. Candidate feeder remains installed; DLSS path is active.'
    }
    'restore' {
        Assert-Stopped
        Set-IniValue $Ini 'M3K' 'FSRProof' '0'
        if(Test-Path -LiteralPath $Backup){
            Copy-Item -LiteralPath $Backup -Destination $Live -Force
            Remove-Item -LiteralPath $Backup -Force
            Write-Host 'Original production feeder restored and FSRProof set to 0.'
        } else {
            Write-Host 'No FSR-P1 backup exists. FSRProof was set to 0; feeder was not changed.'
        }
    }
    'status' {
        Write-Host "Game: $Game"
        Write-Host "Candidate present: $([bool](Test-Path -LiteralPath $Candidate))"
        Write-Host "Backup present:    $([bool](Test-Path -LiteralPath $Backup))"
        $proof=(Select-String -LiteralPath $Ini -Pattern '^\s*FSRProof\s*=\s*(.+)\s*$' -AllMatches | Select-Object -Last 1)
        Write-Host "FSRProof:          $($(if($proof){$proof.Matches[0].Groups[1].Value}else{'<unset>'}))"
        if(Test-Path -LiteralPath $Live){ Write-Host "Live feeder SHA256: $((Get-FileHash -Algorithm SHA256 $Live).Hash)" }
    }
    'log' {
        if(-not(Test-Path -LiteralPath $Log)){ throw "Log not found yet: $Log" }
        Select-String -LiteralPath $Log -Pattern 'M3K-FSR|FSR 3\.1\.4 DIRECT|delivered by FSR' |
            Select-Object -Last 80 | ForEach-Object { $_.Line }
    }
}
