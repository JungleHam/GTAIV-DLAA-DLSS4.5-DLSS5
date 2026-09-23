[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'
$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
if(-not(Test-Path -LiteralPath $vkPath)){throw "Missing generated source: $vkPath"}
if(-not(Test-Path -LiteralPath $FeederSource)){throw "Missing feeder source: $FeederSource"}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if($count-ne 1){throw "P9C.5 $Label expected once, found $count"}
    return $Text.Replace($Old,$New)
}

$vk=Once $vk 'static UINT g_m3kJitterMode=0; // 0=Auto, otherwise explicit phase count (8/16/32)' 'static UINT g_m3kJitterMode=8; // RTX 4070 Ti SUPER hardware calibration: 8 phases' 'NVIDIA jitter sequence default'
$vk=Once $vk 'static UINT g_m3kJitterCompMode=0; // 0=+X/+Y, 1=-X/-Y, 2=+X/-Y, 3=-X/+Y' 'static UINT g_m3kJitterCompMode=1; // RTX 4070 Ti SUPER hardware calibration: -X/-Y' 'NVIDIA jitter sign default'
$vk=Once $vk 'const UINT rawJitterMode=GetPrivateProfileIntW(L"M3K",L"JitterMode",0,path);' 'const UINT rawJitterMode=GetPrivateProfileIntW(L"M3K",L"JitterMode",8,path);' 'NVIDIA jitter INI fallback'
$vk=Once $vk 'const UINT rawJitterComp=GetPrivateProfileIntW(L"M3K",L"NvidiaJitterCompMode",0,path);' 'const UINT rawJitterComp=GetPrivateProfileIntW(L"M3K",L"NvidiaJitterCompMode",1,path);' 'NVIDIA sign INI fallback'

$uiAnchor='            ImGui::TextDisabled("Full raster jitter stays ON. This changes only the X/Y sign reported to NVIDIA NGX.");'
$uiNew=@'
            ImGui::TextDisabled("Full raster jitter stays ON. This changes only the X/Y sign reported to NVIDIA NGX.");
            ImGui::TextDisabled("Hardware-calibrated default: 8 phases, -X / -Y.");
'@
$feed=Once $feed $uiAnchor $uiNew 'calibrated-default UI note'

$prepare='static void M3kPrepareFrame()'
$at=$vk.IndexOf($prepare,[StringComparison]::Ordinal)
if($at-lt 0){throw 'P9C.5 M3kPrepareFrame anchor missing'}
$marker=@'
static void M3kP9C5LogCalibratedDefaultsOnce()
{
    static bool said=false;
    if(said)return;
    said=true;
    Log("M3K-P9C5: calibrated NVIDIA temporal defaults = 8 phases, -X/-Y; AMD keeps independent FSR phase planning");
}

'@
$vk=$vk.Substring(0,$at)+$marker+$vk.Substring($at)
$body='static void M3kPrepareFrame()'
$vk=Once $vk $body ($body+[Environment]::NewLine+'{'+[Environment]::NewLine+'    M3kP9C5LogCalibratedDefaultsOnce();') 'startup proof hook'
$vk=$vk.Replace('static void M3kPrepareFrame()`r`n{`r`n{','static void M3kPrepareFrame()`r`n{')
$vk=$vk.Replace('static void M3kPrepareFrame()`n{`n{','static void M3kPrepareFrame()`n{')

foreach($m in @(
    'M3K-P9C5: calibrated NVIDIA temporal defaults = 8 phases, -X/-Y; AMD keeps independent FSR phase planning',
    'Hardware-calibrated default: 8 phases, -X / -Y.',
    'GetPrivateProfileIntW(L"M3K",L"JitterMode",8,path)',
    'GetPrivateProfileIntW(L"M3K",L"NvidiaJitterCompMode",1,path)'
)){if(($vk+$feed).IndexOf($m,[StringComparison]::Ordinal)-lt 0){throw "P9C.5 marker missing: $m"}}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'P9C.5 applied: NVIDIA defaults promoted to 8 phases + -X/-Y; AMD temporal planning unchanged.'
