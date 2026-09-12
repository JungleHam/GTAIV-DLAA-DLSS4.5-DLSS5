@rem GTAIV-DLAA-DLSS5 optional DFC/Neural Rendering upgrade. See repository README.
@echo off
setlocal EnableExtensions
set "SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Game = Split-Path -Parent $env:SELF
$Trex = Join-Path $Game '.trex'
$Temp = Join-Path $env:TEMP ("GTAIV_DFC_" + $PID)

$Wanted = @{
    NrHash      = '4b8d19bc3eff58a084f5eca7489c921501c203450169fb82ff4f649a4482ba05'
    DlssHash    = '3975567b8943c53acce397f2b72380092f84f162d00b0d2c7d08a1025c563983'
    ArchiveHash = '91dc4137b1f2d7cdbd7f9eb4de9d33848b59e3af7a747d5d798271ee262eab09'
}

function Fail([string]$m) { throw $m }

function Find-ByHash([string]$Hash, [string[]]$Patterns) {
    $roots = @($Game, (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'))
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($pat in $Patterns) {
            $files = Get-ChildItem -LiteralPath $root -Filter $pat -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                try {
                    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
                    if ($h -eq $Hash) { return $f.FullName }
                } catch {}
            }
        }
    }
    return $null
}

function Copy-IfExists([string]$Src, [string]$Dst) {
    if (Test-Path -LiteralPath $Src) {
        $parent = Split-Path -Parent $Dst
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
    }
}

function Set-FlatKey([string]$Path, [string]$Key, [string]$Value) {
    $text = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
    $pat = '(?im)^\s*' + [regex]::Escape($Key) + '\s*=.*$'
    if ($text -match $pat) { $text = [regex]::Replace($text, $pat, "$Key=$Value") }
    else { if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`r`n" }; $text += "$Key=$Value`r`n" }
    [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Add-ReShadeEarlyLoad([string]$Ini, [string]$Token) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $Ini) { foreach ($l in Get-Content -LiteralPath $Ini) { [void]$lines.Add([string]$l) } }
    $sec = '[ADDON]'; $start = -1
    for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ieq $sec) { $start=$i; break } }
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count-1] -ne '') { [void]$lines.Add('') }
        [void]$lines.Add($sec); [void]$lines.Add("LoadFromDllMain=$Token")
    } else {
        $end=$lines.Count
        for ($i=$start+1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[.+\]\s*$') { $end=$i; break } }
        $found=$false
        for ($i=$start+1; $i -lt $end; $i++) {
            if ($lines[$i] -match '^\s*LoadFromDllMain\s*=') {
                $parts = ($lines[$i] -split '=',2)[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                if ($parts -notcontains $Token) { $parts += $Token }
                $lines[$i] = 'LoadFromDllMain=' + ($parts -join ','); $found=$true; break
            }
        }
        if (-not $found) { $lines.Insert($start+1, "LoadFromDllMain=$Token") }
    }
    [IO.File]::WriteAllLines($Ini, $lines.ToArray(), (New-Object Text.UTF8Encoding($false)))
}

try {
    Write-Host ''; Write-Host '=====================================================' -ForegroundColor Green; Write-Host ' GTA IV DLAA -> DLSS 5 Neural Rendering via DFC' -ForegroundColor Green; Write-Host '=====================================================' -ForegroundColor Green; Write-Host ''

    if (-not (Test-Path -LiteralPath (Join-Path $Game 'GTAIV.exe'))) { Fail 'Put this BAT beside GTAIV.exe.' }
    if (-not (Test-Path -LiteralPath $Trex)) { Fail '.trex is missing. Install/restore the proven b-bridge + DLAA setup first.' }

    foreach ($need in @((Join-Path $Trex 'NvRemixBridge.exe'),(Join-Path $Trex 'ReShade.ini'),(Join-Path $Trex 'dlss5-feed.addon64'),(Join-Path $Trex 'dlss5-feed.cfg'),(Join-Path $Trex 'nvngx_dlss.dll'))) {
        if (-not (Test-Path -LiteralPath $need)) { Fail "Working DLAA prerequisite missing: $need" }
    }

    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV first.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe first.' }

    Write-Host 'Locating the known-good user-supplied DFC/NR files by SHA256...' -ForegroundColor Cyan
    $nr = Find-ByHash $Wanted.NrHash @('nvngx_dlssnr*.dll')
    $arc = Find-ByHash $Wanted.ArchiveHash @('Deep-Fried-Chicken*.7z')
    $dlss = Join-Path $Trex 'nvngx_dlss.dll'

    if (-not $nr) { Fail "Could not find the tested nvngx_dlssnr.dll.`nPut it beside this BAT, on Desktop, or in Downloads." }
    if (-not $arc) { Fail "Could not find the tested Deep-Fried-Chicken .7z.`nPut it beside this BAT, on Desktop, or in Downloads." }

    $baseDlssHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dlss).Hash.ToLowerInvariant()
    if ($baseDlssHash -ne $Wanted.DlssHash) { Fail "The base DLAA nvngx_dlss.dll is not the tested 310.9.1 file.`nExpected SHA256: $($Wanted.DlssHash)`nActual: $baseDlssHash`nRe-run the DLAA installer first." }

    Write-Host "  NR DLL : $nr" -ForegroundColor DarkGray
    Write-Host "  DLSS   : $dlss (already installed by DLAA base)" -ForegroundColor DarkGray
    Write-Host "  DFC    : $arc" -ForegroundColor DarkGray

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Backup = Join-Path $Trex ("_PRE_DFC_BACKUP_" + $stamp)
    New-Item -ItemType Directory -Path $Backup -Force | Out-Null
    foreach ($name in @('ReShade.ini','dlss5-feed.cfg','nvngx_dlss.dll','nvngx_dlssnr.dll','deep-fried-chicken.addon64','deep-fried-chicken-nvngx.dll','deep-fried-chicken.cfg','renodx-dlss5.addon64','renodx-dlss.addon64','alexs-toolkit.addon64','dlssnr-cascade.addon64','dlss5-dx11-bridge.addon64')) { Copy-IfExists (Join-Path $Trex $name) (Join-Path $Backup $name) }
    Write-Host "Backup created: $Backup" -ForegroundColor DarkGray

    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force }
    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    $extract = Join-Path $Temp 'DFC'; New-Item -ItemType Directory -Path $extract -Force | Out-Null

    $seven = $null
    foreach ($candidate in @("$env:ProgramFiles\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe","$env:LOCALAPPDATA\Programs\7-Zip\7z.exe")) { if ($candidate -and (Test-Path -LiteralPath $candidate)) { $seven=$candidate; break } }
    if (-not $seven) {
        $seven = Join-Path $Temp '7zr.exe'
        Write-Host '7-Zip not found; downloading official standalone 7zr.exe...' -ForegroundColor Cyan
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) { & curl.exe -L --fail --retry 3 --silent --show-error -o $seven 'https://www.7-zip.org/a/7zr.exe'; if ($LASTEXITCODE -ne 0) { Fail 'Could not download 7zr.exe.' } }
        else { Invoke-WebRequest -UseBasicParsing -Uri 'https://www.7-zip.org/a/7zr.exe' -OutFile $seven }
    }

    Write-Host 'Extracting Deep Fried Chicken (password: chicken)...' -ForegroundColor Cyan
    & $seven x "-pchicken" '-y' "-o$extract" $arc | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'DFC extraction failed. Wrong password/archive or 7-Zip error.' }

    $addon = Get-ChildItem -LiteralPath $extract -Filter 'deep-fried-chicken.addon64' -File -Recurse | Select-Object -First 1
    $bridge = Get-ChildItem -LiteralPath $extract -Filter 'deep-fried-chicken-nvngx.dll' -File -Recurse | Select-Object -First 1
    $cfg = Get-ChildItem -LiteralPath $extract -Filter 'deep-fried-chicken.cfg' -File -Recurse | Select-Object -First 1
    if (-not $addon) { Fail 'Archive extracted, but deep-fried-chicken.addon64 was not found.' }
    if (-not $bridge) { Fail 'Archive extracted, but deep-fried-chicken-nvngx.dll was not found.' }
    if (-not $cfg) { Fail 'Archive extracted, but deep-fried-chicken.cfg was not found.' }

    Write-Host 'Retiring conflicting neural providers if present...' -ForegroundColor Cyan
    foreach ($pat in @('renodx-dlss5.addon64','renodx-dlss.addon64','alexs-toolkit.addon64','dlssnr-cascade*.addon64','dlss5-dx11-bridge.addon64')) { Get-ChildItem -LiteralPath $Trex -Filter $pat -File -ErrorAction SilentlyContinue | Remove-Item -Force }

    Write-Host 'Installing DFC + tested DLSSNR runtime...' -ForegroundColor Cyan
    Copy-Item -LiteralPath $addon.FullName -Destination (Join-Path $Trex 'deep-fried-chicken.addon64') -Force
    Copy-Item -LiteralPath $bridge.FullName -Destination (Join-Path $Trex 'deep-fried-chicken-nvngx.dll') -Force
    Copy-Item -LiteralPath $cfg.FullName -Destination (Join-Path $Trex 'deep-fried-chicken.cfg') -Force
    Copy-Item -LiteralPath $nr -Destination (Join-Path $Trex 'nvngx_dlssnr.dll') -Force

    $dfcCfg = Join-Path $Trex 'deep-fried-chicken.cfg'
    Set-FlatKey $dfcCfg 'arm' '1'; Set-FlatKey $dfcCfg 'enabled' '1'; Set-FlatKey $dfcCfg 'safe_neutral_start' '0'
    Add-ReShadeEarlyLoad (Join-Path $Trex 'ReShade.ini') 'deep-fried-chicken.addon64'
    $feedCfg = Join-Path $Trex 'dlss5-feed.cfg'
    Set-FlatKey $feedCfg 'enabled' '1'; Set-FlatKey $feedCfg 'mode' '2'; Set-FlatKey $feedCfg 'work_resolution' '100'

    $nrInstalled = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Trex 'nvngx_dlssnr.dll')).Hash.ToLowerInvariant()
    $dlssInstalled = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Trex 'nvngx_dlss.dll')).Hash.ToLowerInvariant()
    if ($nrInstalled -ne $Wanted.NrHash) { Fail 'Installed nvngx_dlssnr.dll hash mismatch.' }
    if ($dlssInstalled -ne $Wanted.DlssHash) { Fail 'Installed nvngx_dlss.dll hash mismatch.' }
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path -LiteralPath (Join-Path $Trex 'deep-fried-chicken.addon64'))) { Fail 'deep-fried-chicken.addon64 disappeared after copy. Antivirus/Defender may have quarantined it.' }

    $manifest = @"
GTA IV DLSS 5 / Deep Fried Chicken upgrade
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Base:
- Existing proven GTA IV + FusionFix + b-bridge + ReShade + Lumenite + DLSS5-Feeder DLAA setup

Added:
- Deep Fried Chicken archive supplied by user: $(Split-Path -Leaf $arc)
  SHA256: $($Wanted.ArchiveHash)
- nvngx_dlssnr.dll supplied by user
  SHA256: $($Wanted.NrHash)
- nvngx_dlss.dll inherited from the verified DLAA base
  SHA256: $($Wanted.DlssHash)

DFC:
- arm=1
- enabled=1
- safe_neutral_start=0
- LoadFromDllMain=deep-fried-chicken.addon64

Feeder:
- enabled=1
- mode=2
- work_resolution=100

Backup:
$Backup

Expected success evidence:
- Feeder: Deep Fried Chicken interop ABI 1 / ARMED
- DFC: feeder_marker=1 legacy_exact=0
- DFC: standalone feature 18 created
- DFC: neural frames/evaluates without failure
"@
    [IO.File]::WriteAllText((Join-Path $Trex 'DFC_INSTALL_MANIFEST.txt'),$manifest,(New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force }

    Write-Host ''; Write-Host '=====================================================' -ForegroundColor Green; Write-Host ' INSTALLED: DLSS 5 NEURAL RENDERING + DFC' -ForegroundColor Green; Write-Host '=====================================================' -ForegroundColor Green
    Write-Host 'Launch GTA IV normally. Verify .trex\dlss5-feed.log and .trex\deep-fried-chicken.log.' -ForegroundColor White
    Write-Host 'If DFC requests a restart, close BOTH GTAIV and NvRemixBridge and relaunch once.' -ForegroundColor DarkGray
    Read-Host 'Press Enter to close'; exit 0
}
catch {
    Write-Host ''; Write-Host 'FAILED:' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'Your pre-DFC backup was preserved inside .trex\_PRE_DFC_BACKUP_*.' -ForegroundColor Yellow
    if (Test-Path -LiteralPath $Temp) { try { Remove-Item -LiteralPath $Temp -Recurse -Force } catch {} }
    Read-Host 'Press Enter to close'; exit 1
}
