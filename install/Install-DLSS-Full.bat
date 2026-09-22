@echo off
setlocal
set "GTAIV_SETUP_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:GTAIV_SETUP_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Self=$env:GTAIV_SETUP_SELF;$Repo='JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5';$RuntimeTag='v1.1.0'
$ReleaseApi='https://api.github.com/repos/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases/tags/v1.1.0'
$RuntimeAsset='GTAIV-DLSS-Full-Runtime.zip'
$RuntimeZipHash='A0796FA04DFACEC7997B08BEFE1933EFBB17D2BC62478CB41B8C89750674CEE3'
$RuntimeHashes=@{
 'd3d9.dll'='45717A8F8C9F3A7E38A8187CC965B3219545FD4D331F61DA28908433AD8CA20B';
 'NvRemixBridge.exe'='E4D5C00B622825E73373E489D5E47E8319DC6043999D2B062FF4A8031F916F32';
 'd3d9vk_x64.dll'='370BE394DE7BFC612D227CBE4B2A57A4AB5C23A420BE00AA839876DEF653DF97';
 'dlss5-feed.addon64'='B6D7D9B050C4F32642A528E7700F38A0510795C7D61D30665DC96AF270B9ED27';
 'm3k\m3k-nvngx.dll'='E96B15E97028E2F3BA44854BE85A76BCD7C47B2062EE96CE05F7B8FFD4CE28D6';
 'M3K_Sharpen.fx'='20E2F9C918B2AAEC1B1C19CF732038506DC604B3455FAEEAD3147A11F0275429'
}
$Nr50DllHash='E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$Nr40DllHash='4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05'
$NrDllInput=$env:GTAIV_SETUP_NR_DLL
$Temp=Join-Path $env:TEMP ("GTAIV_DLSS_FULL_RELEASE_"+$PID);$InstallStarted=$false;$Backup=$null
function Fail([string]$m){throw $m}
function Resolve-ProjectAssetUrl([string]$AssetName){$headers=@{'User-Agent'='GTAIV-DLSS-Setup'};$release=Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri $ReleaseApi;$asset=@($release.assets|Where-Object{$_.name -eq $AssetName})|Select-Object -First 1;if(-not $asset -or -not $asset.browser_download_url){Fail "Project release asset was not found: $AssetName"};return [string]$asset.browser_download_url}
function Is-Admin{$id=[Security.Principal.WindowsIdentity]::GetCurrent();$p=New-Object Security.Principal.WindowsPrincipal($id);return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
function Download([string]$u,[string]$p){Write-Host "Downloading project release asset: $u" -ForegroundColor DarkGray;$curl=Get-Command curl.exe -ErrorAction SilentlyContinue;if($curl){& curl.exe -L --fail --retry 3 --connect-timeout 20 --silent --show-error -o $p $u;if($LASTEXITCODE -ne 0){Fail "Download failed: $u"}}else{Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p};if(-not(Test-Path -LiteralPath $p)){Fail "Downloaded file is missing: $p"}}
function Assert-SHA256([string]$p,[string]$e){$a=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant();if($a -ne $e.ToUpperInvariant()){Fail "SHA256 mismatch for $p`nExpected: $e`nActual:   $a"}}
function Resolve-GameFolder{if($env:GTAIV_SETUP_GAME){return(Resolve-Path -LiteralPath $env:GTAIV_SETUP_GAME).Path};$raw=(Read-Host 'GTA IV folder').Trim().Trim('"');if((Test-Path -LiteralPath $raw -PathType Leaf)-and([IO.Path]::GetFileName($raw)-ieq'GTAIV.exe')){$raw=Split-Path -Parent $raw};if(Test-Path -LiteralPath (Join-Path $raw 'GTAIV.exe')){return(Resolve-Path -LiteralPath $raw).Path};Fail 'GTAIV.exe was not found.'}
function Write-NoBom([string]$p,[string[]]$l){[IO.File]::WriteAllLines($p,$l,(New-Object Text.UTF8Encoding($false)))}
function Set-KeyEquals([string]$Path,[string]$Key,[string]$Value){$text=if(Test-Path -LiteralPath $Path){[IO.File]::ReadAllText($Path)}else{''};$pat='(?m)^\s*'+[regex]::Escape($Key)+'\s*=\s*.*$';$line="$Key = $Value";if($text -match $pat){$text=[regex]::Replace($text,$pat,$line)}else{if($text.Length -gt 0 -and -not $text.EndsWith("`n")){$text+="`r`n"};$text+=$line+"`r`n"};[IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))}
function Ensure-ReShadeTechnique([string]$Path,[string]$Technique){
 if(-not(Test-Path -LiteralPath $Path)){return}
 $text=[IO.File]::ReadAllText($Path)
 foreach($key in @('Techniques','TechniqueSorting')){
  $pat='(?m)^'+[regex]::Escape($key)+'=(.*){if(-not(Test-Path -LiteralPath $s)){return};$p=Split-Path -Parent $d;if($p -and -not(Test-Path -LiteralPath $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null};if(Test-Path -LiteralPath $s -PathType Container){Copy-Item -LiteralPath $s -Destination $d -Recurse -Force}else{Copy-Item -LiteralPath $s -Destination $d -Force}}
function Save-DlaaBaseline([string]$Game,[string]$Trex){$b=Join-Path $Game '_DLSS_FULL_DLAA_BASELINE';if(Test-Path -LiteralPath $b){Remove-Item -LiteralPath $b -Recurse -Force};New-Item -ItemType Directory -Path $b -Force|Out-Null;foreach($rel in @('d3d9.dll','d3d9Hooked.dll','dxvk.conf','commandline.txt','DLAA_INSTALL_MANIFEST.txt','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\bridge.conf','.trex\ReShade.ini','.trex\ReShadePreset.ini','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\nvngx_dlss.dll','.trex\reshade-shaders')){Copy-Path (Join-Path $Game $rel) (Join-Path $b $rel)};return $b}
function Snapshot-Current([string]$Game,[string]$Dest){New-Item -ItemType Directory -Path $Dest -Force|Out-Null;foreach($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat','DLSS_FULL_INSTALLED.txt')){Copy-Path (Join-Path $Game $rel) (Join-Path $Dest $rel)}}
function Restore-Snapshot([string]$Game,[string]$Dest){foreach($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat','DLSS_FULL_INSTALLED.txt')){$dst=Join-Path $Game $rel;if(Test-Path -LiteralPath $dst){Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue};Copy-Path (Join-Path $Dest $rel) $dst}}
function Resolve-LocalSupportFile([string]$name){$p=Join-Path (Split-Path -Parent $Self) $name;if(Test-Path -LiteralPath $p){return $p};Fail "$name is missing from the installer package."}

if(-not(Is-Admin)){Write-Host 'Administrator permission is required.' -ForegroundColor Yellow;$p=Start-Process -FilePath $Self -Verb RunAs -Wait -PassThru;exit $p.ExitCode}
try{
 Write-Host '';Write-Host '============================================================' -ForegroundColor Green;Write-Host ' GTA IV - DLSS Full + Neural Rendering' -ForegroundColor Green;Write-Host '============================================================' -ForegroundColor Green
 $Game=Resolve-GameFolder;$Trex=Join-Path $Game '.trex';foreach($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\nvngx_dlss.dll')){if(-not(Test-Path -LiteralPath (Join-Path $Game $rel))){Fail "DLAA/ReShade step is incomplete; missing $rel."}}
 if(Get-Process GTAIV -ErrorAction SilentlyContinue){Fail 'Close GTA IV first.'};if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe first.'}
 if(-not $NrDllInput -or -not(Test-Path -LiteralPath $NrDllInput -PathType Leaf)){Fail 'Select nvngx_dlssnr.dll in the installer.'}
 $gpu=Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'NVIDIA'}|Select-Object -First 1;$gpuName=if($gpu){[string]$gpu.Name}else{'NVIDIA GPU not detected by Windows'}
 if($gpuName -match 'RTX\s*50'){$flavor='RTX50';$nrLabel='Original NVIDIA-signed DLSS NR 310.8 (RTX 50)';$nrDll=$Nr50DllHash;$sig=Get-AuthenticodeSignature -LiteralPath $NrDllInput;if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA'){Fail 'RTX 50 NR DLL is not the expected NVIDIA-signed runtime.'}}
 elseif($gpuName -match 'RTX\s*40'){$flavor='RTX40';$nrLabel='RTX 40 compatibility DLSS NR 310.8 (project-tested modded DLL)';$nrDll=$Nr40DllHash}
 else{Fail "Full DLSS release support currently requires RTX 40/50. Detected: $gpuName"}
 Assert-SHA256 $NrDllInput $nrDll
 Write-Host '';Write-Host "GPU: $gpuName";Write-Host "NR:  $nrLabel";Write-Host 'The NR DLL was selected and validated by setup.' -ForegroundColor Green
 $ok=if($env:GTAIV_SETUP_GAME){'y'}else{Read-Host 'Continue? [Y/n]'};if($ok -and $ok -notmatch '^(y|yes)$'){exit 0}
 New-Item -ItemType Directory -Path $Temp -Force|Out-Null;$runtimeZip=Join-Path $Temp 'runtime.zip';$runtimeDir=Join-Path $Temp 'runtime'
 if($env:GTAIV_SETUP_PROJECT_RUNTIME -and (Test-Path -LiteralPath $env:GTAIV_SETUP_PROJECT_RUNTIME -PathType Leaf)){Write-Host 'Using local project runtime beside setup EXE.' -ForegroundColor DarkGray;Copy-Item -LiteralPath $env:GTAIV_SETUP_PROJECT_RUNTIME -Destination $runtimeZip -Force}else{$runtimeUrl=Resolve-ProjectAssetUrl $RuntimeAsset;Download $runtimeUrl $runtimeZip};Assert-SHA256 $runtimeZip $RuntimeZipHash;Expand-Archive -LiteralPath $runtimeZip -DestinationPath $runtimeDir -Force;foreach($rel in $RuntimeHashes.Keys){$p=Join-Path $runtimeDir $rel;if(-not(Test-Path -LiteralPath $p)){Fail "Runtime archive is missing $rel"};Assert-SHA256 $p $RuntimeHashes[$rel]}
 $baseline=Save-DlaaBaseline $Game $Trex;$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$Backup=Join-Path $Game ("_DLSS_FULL_PREINSTALL_BACKUP_"+$stamp);Snapshot-Current $Game $Backup
 $InstallStarted=$true;Copy-Item -LiteralPath (Join-Path $runtimeDir 'd3d9.dll') -Destination (Join-Path $Game 'd3d9.dll') -Force;Copy-Item -LiteralPath (Join-Path $runtimeDir 'NvRemixBridge.exe') -Destination (Join-Path $Trex 'NvRemixBridge.exe') -Force;Copy-Item -LiteralPath (Join-Path $runtimeDir 'd3d9vk_x64.dll') -Destination (Join-Path $Trex 'd3d9vk_x64.dll') -Force;Copy-Item -LiteralPath (Join-Path $runtimeDir 'dlss5-feed.addon64') -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force;$shaderDir=Join-Path $Trex 'reshade-shaders\Shaders';New-Item -ItemType Directory -Path $shaderDir -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $runtimeDir 'M3K_Sharpen.fx') -Destination (Join-Path $shaderDir 'M3K_Sharpen.fx') -Force;$presetPath=Join-Path $Trex 'ReShadePreset.ini';Ensure-ReShadeTechnique $presetPath 'M3K_Sharpen@M3K_Sharpen.fx';New-Item -ItemType Directory -Path (Join-Path $Trex 'm3k') -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $runtimeDir 'm3k\m3k-nvngx.dll') -Destination (Join-Path $Trex 'm3k\m3k-nvngx.dll') -Force;Copy-Item -LiteralPath $NrDllInput -Destination (Join-Path $Trex 'm3k\nvngx_dlssnr.dll') -Force
 foreach($rel in $RuntimeHashes.Keys){if($rel -eq 'm3k\m3k-nvngx.dll'){Assert-SHA256 (Join-Path $Trex $rel) $RuntimeHashes[$rel]}elseif($rel -in @('d3d9.dll')){Assert-SHA256 (Join-Path $Game $rel) $RuntimeHashes[$rel]}elseif($rel -in @('NvRemixBridge.exe','d3d9vk_x64.dll','dlss5-feed.addon64')){Assert-SHA256 (Join-Path $Trex $rel) $RuntimeHashes[$rel]}}
 Assert-SHA256 (Join-Path $Trex 'm3k\nvngx_dlssnr.dll') $nrDll
 Write-NoBom (Join-Path $Trex 'm3k-nr.ini') @('[M3K]','; GTA IV DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering','MasterEnabled=1','LastSRProfile=0','LastNRMode=0','Mode=0','SourceProof=0','SRProof=1','RenderWidth=1485','RenderHeight=835','OutputWidth=0','OutputHeight=0','AutoResizeWindow=1','VirtualizeGameClient=1','NRPasses=1','SRProfile=0','ProjectionProbe=0','TemporalJitter=1','JitterPhases=8','JitterMode=8','BalancedProbe=0','ManualRender=0','ManualRenderWidth=0','ManualRenderHeight=0','StartupPrime=1','StartupPrimeWidth=1485','StartupPrimeHeight=835','StartupPrimeFrames=180')
 $feedCfg=Join-Path $Trex 'dlss5-feed.cfg';Set-KeyEquals $feedCfg 'enabled' '1';Set-KeyEquals $feedCfg 'mode' '2';Set-KeyEquals $feedCfg 'work_resolution' '100'
 Copy-Item -LiteralPath (Resolve-LocalSupportFile 'DLSS-Full-Control.bat') -Destination (Join-Path $Game 'DLSS-Full-Control.bat') -Force;Copy-Item -LiteralPath (Resolve-LocalSupportFile 'Uninstall-DLSS-Full.bat') -Destination (Join-Path $Game 'Uninstall-DLSS-Full.bat') -Force
 Write-NoBom (Join-Path $Game 'DLSS_FULL_INSTALLED.txt') @('GTA IV DLSS Full clean installation receipt',"Installed=$(Get-Date -Format o)",'DefaultDLSSQuality=DLAA Native','NeuralRendering=installed-off-by-default',"NRRuntimeFlavor=$flavor", "NRRuntimeLabel=$nrLabel", "NRRuntimeSHA256=$nrDll", "DlaaBaseline=$baseline", "Backup=$Backup")
 Write-Host '';Write-Host 'DONE - DLSS Full installed.' -ForegroundColor Green;Write-Host 'Initial DLSS profile: DLAA Native' -ForegroundColor White;Write-Host 'Neural Rendering: INSTALLED, but OFF for the first launch.' -ForegroundColor Yellow;Write-Host 'After verifying DLSS 4.5, enable NR from Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS if wanted.' -ForegroundColor White;Start-Sleep -Seconds 3;exit 0
}catch{Write-Host '';Write-Host ('INSTALL FAILED: '+$_.Exception.Message) -ForegroundColor Red;if($InstallStarted -and $Backup -and(Test-Path -LiteralPath $Backup)){try{Restore-Snapshot $Game $Backup;Write-Host 'Rollback completed.' -ForegroundColor Green}catch{Write-Host ('Rollback error: '+$_.Exception.Message) -ForegroundColor Red}};Read-Host 'Press Enter to close';exit 1}
finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}}

  $m=[regex]::Match($text,$pat)
  if($m.Success){
   $items=@($m.Groups[1].Value.Split(',')|ForEach-Object{$_.Trim()}|Where-Object{$_ -and $_ -ne $Technique})
   $feed='DLSS5_Feed@DLSS5_Feed.fx'
   $idx=[Array]::IndexOf($items,$feed)
   if($idx -ge 0){
    $before=@($items[0..$idx]);$after=@()
    if(($idx+1)-lt $items.Count){$after=@($items[($idx+1)..($items.Count-1)])}
    $items=@($before+$Technique+$after)
   }else{$items=@($items+$Technique)}
   $line=$key+'='+($items -join ',')
   $text=$text.Substring(0,$m.Index)+$line+$text.Substring($m.Index+$m.Length)
  }else{
   if($text.Length -gt 0 -and -not $text.EndsWith("`n")){$text+="`r`n"}
   $text+=$key+'='+$Technique+"`r`n"
  }
 }
 [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}
function Copy-Path([string]$s,[string]$d){if(-not(Test-Path -LiteralPath $s)){return};$p=Split-Path -Parent $d;if($p -and -not(Test-Path -LiteralPath $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null};if(Test-Path -LiteralPath $s -PathType Container){Copy-Item -LiteralPath $s -Destination $d -Recurse -Force}else{Copy-Item -LiteralPath $s -Destination $d -Force}}
function Save-DlaaBaseline([string]$Game,[string]$Trex){$b=Join-Path $Game '_DLSS_FULL_DLAA_BASELINE';if(Test-Path -LiteralPath $b){Remove-Item -LiteralPath $b -Recurse -Force};New-Item -ItemType Directory -Path $b -Force|Out-Null;foreach($rel in @('d3d9.dll','d3d9Hooked.dll','dxvk.conf','commandline.txt','DLAA_INSTALL_MANIFEST.txt','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\bridge.conf','.trex\ReShade.ini','.trex\ReShadePreset.ini','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\nvngx_dlss.dll','.trex\reshade-shaders')){Copy-Path (Join-Path $Game $rel) (Join-Path $b $rel)};return $b}
function Snapshot-Current([string]$Game,[string]$Dest){New-Item -ItemType Directory -Path $Dest -Force|Out-Null;foreach($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat','DLSS_FULL_INSTALLED.txt')){Copy-Path (Join-Path $Game $rel) (Join-Path $Dest $rel)}}
function Restore-Snapshot([string]$Game,[string]$Dest){foreach($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll','DLSS-Full-Control.bat','Uninstall-DLSS-Full.bat','DLSS_FULL_INSTALLED.txt')){$dst=Join-Path $Game $rel;if(Test-Path -LiteralPath $dst){Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue};Copy-Path (Join-Path $Dest $rel) $dst}}
function Resolve-LocalSupportFile([string]$name){$p=Join-Path (Split-Path -Parent $Self) $name;if(Test-Path -LiteralPath $p){return $p};Fail "$name is missing from the installer package."}

if(-not(Is-Admin)){Write-Host 'Administrator permission is required.' -ForegroundColor Yellow;$p=Start-Process -FilePath $Self -Verb RunAs -Wait -PassThru;exit $p.ExitCode}
try{
 Write-Host '';Write-Host '============================================================' -ForegroundColor Green;Write-Host ' GTA IV - DLSS Full + Neural Rendering' -ForegroundColor Green;Write-Host '============================================================' -ForegroundColor Green
 $Game=Resolve-GameFolder;$Trex=Join-Path $Game '.trex';foreach($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg','.trex\nvngx_dlss.dll')){if(-not(Test-Path -LiteralPath (Join-Path $Game $rel))){Fail "DLAA/ReShade step is incomplete; missing $rel."}}
 if(Get-Process GTAIV -ErrorAction SilentlyContinue){Fail 'Close GTA IV first.'};if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe first.'}
 if(-not $NrDllInput -or -not(Test-Path -LiteralPath $NrDllInput -PathType Leaf)){Fail 'Select nvngx_dlssnr.dll in the installer.'}
 $gpu=Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'NVIDIA'}|Select-Object -First 1;$gpuName=if($gpu){[string]$gpu.Name}else{'NVIDIA GPU not detected by Windows'}
 if($gpuName -match 'RTX\s*50'){$flavor='RTX50';$nrLabel='Original NVIDIA-signed DLSS NR 310.8 (RTX 50)';$nrDll=$Nr50DllHash;$sig=Get-AuthenticodeSignature -LiteralPath $NrDllInput;if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA'){Fail 'RTX 50 NR DLL is not the expected NVIDIA-signed runtime.'}}
 elseif($gpuName -match 'RTX\s*40'){$flavor='RTX40';$nrLabel='RTX 40 compatibility DLSS NR 310.8 (project-tested modded DLL)';$nrDll=$Nr40DllHash}
 else{Fail "Full DLSS release support currently requires RTX 40/50. Detected: $gpuName"}
 Assert-SHA256 $NrDllInput $nrDll
 Write-Host '';Write-Host "GPU: $gpuName";Write-Host "NR:  $nrLabel";Write-Host 'The NR DLL was selected and validated by setup.' -ForegroundColor Green
 $ok=if($env:GTAIV_SETUP_GAME){'y'}else{Read-Host 'Continue? [Y/n]'};if($ok -and $ok -notmatch '^(y|yes)$'){exit 0}
 New-Item -ItemType Directory -Path $Temp -Force|Out-Null;$runtimeZip=Join-Path $Temp 'runtime.zip';$runtimeDir=Join-Path $Temp 'runtime'
 if($env:GTAIV_SETUP_PROJECT_RUNTIME -and (Test-Path -LiteralPath $env:GTAIV_SETUP_PROJECT_RUNTIME -PathType Leaf)){Write-Host 'Using local project runtime beside setup EXE.' -ForegroundColor DarkGray;Copy-Item -LiteralPath $env:GTAIV_SETUP_PROJECT_RUNTIME -Destination $runtimeZip -Force}else{$runtimeUrl=Resolve-ProjectAssetUrl $RuntimeAsset;Download $runtimeUrl $runtimeZip};Assert-SHA256 $runtimeZip $RuntimeZipHash;Expand-Archive -LiteralPath $runtimeZip -DestinationPath $runtimeDir -Force;foreach($rel in $RuntimeHashes.Keys){$p=Join-Path $runtimeDir $rel;if(-not(Test-Path -LiteralPath $p)){Fail "Runtime archive is missing $rel"};Assert-SHA256 $p $RuntimeHashes[$rel]}
 $baseline=Save-DlaaBaseline $Game $Trex;$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$Backup=Join-Path $Game ("_DLSS_FULL_PREINSTALL_BACKUP_"+$stamp);Snapshot-Current $Game $Backup
 $InstallStarted=$true;Copy-Item -LiteralPath (Join-Path $runtimeDir 'd3d9.dll') -Destination (Join-Path $Game 'd3d9.dll') -Force;Copy-Item -LiteralPath (Join-Path $runtimeDir 'NvRemixBridge.exe') -Destination (Join-Path $Trex 'NvRemixBridge.exe') -Force;Copy-Item -LiteralPath (Join-Path $runtimeDir 'd3d9vk_x64.dll') -Destination (Join-Path $Trex 'd3d9vk_x64.dll') -Force;Copy-Item -LiteralPath (Join-Path $runtimeDir 'dlss5-feed.addon64') -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force;New-Item -ItemType Directory -Path (Join-Path $Trex 'm3k') -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $runtimeDir 'm3k\m3k-nvngx.dll') -Destination (Join-Path $Trex 'm3k\m3k-nvngx.dll') -Force;Copy-Item -LiteralPath $NrDllInput -Destination (Join-Path $Trex 'm3k\nvngx_dlssnr.dll') -Force
 foreach($rel in $RuntimeHashes.Keys){if($rel -eq 'm3k\m3k-nvngx.dll'){Assert-SHA256 (Join-Path $Trex $rel) $RuntimeHashes[$rel]}elseif($rel -in @('d3d9.dll')){Assert-SHA256 (Join-Path $Game $rel) $RuntimeHashes[$rel]}elseif($rel -in @('NvRemixBridge.exe','d3d9vk_x64.dll','dlss5-feed.addon64')){Assert-SHA256 (Join-Path $Trex $rel) $RuntimeHashes[$rel]}}
 Assert-SHA256 (Join-Path $Trex 'm3k\nvngx_dlssnr.dll') $nrDll
 Write-NoBom (Join-Path $Trex 'm3k-nr.ini') @('[M3K]','; GTA IV DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering','MasterEnabled=1','LastSRProfile=2','LastNRMode=0','Mode=0','SourceProof=0','SRProof=1','RenderWidth=1485','RenderHeight=835','OutputWidth=0','OutputHeight=0','AutoResizeWindow=1','VirtualizeGameClient=1','NRPasses=1','SRProfile=2','ProjectionProbe=0','TemporalJitter=1','BalancedProbe=0','ManualRender=0','ManualRenderWidth=0','ManualRenderHeight=0','StartupPrime=1','StartupPrimeWidth=1485','StartupPrimeHeight=835','StartupPrimeFrames=180')
 $feedCfg=Join-Path $Trex 'dlss5-feed.cfg';Set-KeyEquals $feedCfg 'enabled' '1';Set-KeyEquals $feedCfg 'mode' '2';Set-KeyEquals $feedCfg 'work_resolution' '100'
 Copy-Item -LiteralPath (Resolve-LocalSupportFile 'DLSS-Full-Control.bat') -Destination (Join-Path $Game 'DLSS-Full-Control.bat') -Force;Copy-Item -LiteralPath (Resolve-LocalSupportFile 'Uninstall-DLSS-Full.bat') -Destination (Join-Path $Game 'Uninstall-DLSS-Full.bat') -Force
 Write-NoBom (Join-Path $Game 'DLSS_FULL_INSTALLED.txt') @('GTA IV DLSS Full clean installation receipt',"Installed=$(Get-Date -Format o)",'DefaultDLSSQuality=Quality','NeuralRendering=installed-off-by-default',"NRRuntimeFlavor=$flavor", "NRRuntimeLabel=$nrLabel", "NRRuntimeSHA256=$nrDll", "DlaaBaseline=$baseline", "Backup=$Backup")
 Write-Host '';Write-Host 'DONE - DLSS Full installed.' -ForegroundColor Green;Write-Host 'Initial DLSS profile: Quality' -ForegroundColor White;Write-Host 'Neural Rendering: INSTALLED, but OFF for the first launch.' -ForegroundColor Yellow;Write-Host 'After verifying DLSS 4.5, enable NR from Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS if wanted.' -ForegroundColor White;Start-Sleep -Seconds 3;exit 0
}catch{Write-Host '';Write-Host ('INSTALL FAILED: '+$_.Exception.Message) -ForegroundColor Red;if($InstallStarted -and $Backup -and(Test-Path -LiteralPath $Backup)){try{Restore-Snapshot $Game $Backup;Write-Host 'Rollback completed.' -ForegroundColor Green}catch{Write-Host ('Rollback error: '+$_.Exception.Message) -ForegroundColor Red}};Read-Host 'Press Enter to close';exit 1}
finally{if(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}}
