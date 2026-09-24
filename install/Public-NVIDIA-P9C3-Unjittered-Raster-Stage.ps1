[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'
$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
if(-not(Test-Path -LiteralPath $vkPath)){throw "Missing generated source: $vkPath"}
$vk=[IO.File]::ReadAllText($vkPath)

$old=@'
    g_m3kMasterEnabled=true;
    M3kWriteMasterIni(L"MasterEnabled",1);
    M3kWriteMasterIni(L"TemporalJitter",1);

    if(g_m3kScalingTechnologyActive==1u)
'@
$new=@'
    g_m3kMasterEnabled=true;
    M3kWriteMasterIni(L"MasterEnabled",1);
    const bool m3kBackendWantsRasterJitter=g_m3kScalingTechnologyActive==2u;
    M3kWriteMasterIni(L"TemporalJitter",m3kBackendWantsRasterJitter?1u:0u);
    Log("M3K-P9C3: backend raster jitter policy %s -> TemporalJitter=%u",
        M3kScalingTechnologyName(g_m3kScalingTechnologyActive),
        m3kBackendWantsRasterJitter?1u:0u);

    if(g_m3kScalingTechnologyActive==1u)
'@
$count=([regex]::Matches($vk,[regex]::Escape($old))).Count
if($count-ne 1){throw "P9C.3 master-enable anchor expected once, found $count"}
$vk=$vk.Replace($old,$new)

$oldLog='Log("M3K-MASTER-V2: OFF stage 1 - switching to native source; jitter stays ON during resize");'
$newLog='Log("M3K-MASTER-V2: OFF stage 1 - switching to native source; retaining current backend jitter policy during resize");'
if(([regex]::Matches($vk,[regex]::Escape($oldLog))).Count-ne 1){throw 'P9C.3 stage1 log anchor missing/non-unique'}
$vk=$vk.Replace($oldLog,$newLog)

foreach($marker in @(
    'M3K-P9C3: backend raster jitter policy %s -> TemporalJitter=%u',
    'm3kBackendWantsRasterJitter=g_m3kScalingTechnologyActive==2u',
    'retaining current backend jitter policy during resize'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "P9C.3 verification marker missing: $marker"}
}
[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
Write-Host 'P9C.3 applied: NVIDIA raster jitter OFF, AMD raster jitter ON; switching/lifecycle unchanged.'
