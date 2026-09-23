[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR P6 stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
if(-not(Test-Path -LiteralPath $vkPath)){throw "Missing generated source: $vkPath"}
$vk=[IO.File]::ReadAllText($vkPath)

# P5C hardware projection telemetry:
#   425 accepted samples total
#   424 samples at the full 1708x960 gameplay viewport
#   FOV: overwhelmingly 45.0 degrees
#   near: ~0.050000
#   far: 422/424 full-size samples cluster at ~1500
# Two ~24.7k far-plane samples are treated as secondary/alternate projections,
# not the main scene camera contract. INI overrides remain available.

$vk=Once $vk 'static float g_m3kFsrCameraNear=0.1f;' 'static float g_m3kFsrCameraNear=0.05f;' 'camera near default'
$vk=Once $vk 'static float g_m3kFsrCameraFar=1000.0f;' 'static float g_m3kFsrCameraFar=1500.0f;' 'camera far default'
$vk=Once $vk 'static float g_m3kFsrCameraFovY=1.22173048f; // provisional 70 degrees; logged loudly' 'static float g_m3kFsrCameraFovY=0.7853981633974483f; // P5C hardware-calibrated 45 degrees' 'camera FOV default'

$vk=Once $vk 'const float fsrCameraNear=m3kFsrReadFloat(L"FSRCameraNear",0.1f);' 'const float fsrCameraNear=m3kFsrReadFloat(L"FSRCameraNear",0.05f);' 'INI near fallback'
$vk=Once $vk 'const float fsrCameraFar=m3kFsrReadFloat(L"FSRCameraFar",1000.0f);' 'const float fsrCameraFar=m3kFsrReadFloat(L"FSRCameraFar",1500.0f);' 'INI far fallback'
$vk=Once $vk 'float fsrCameraFovDeg=m3kFsrReadFloat(L"FSRCameraFovYDegrees",70.0f);' 'float fsrCameraFovDeg=m3kFsrReadFloat(L"FSRCameraFovYDegrees",45.0f);' 'INI FOV fallback'
$vk=Once $vk 'if(fsrCameraFovDeg<10.0f||fsrCameraFovDeg>170.0f)fsrCameraFovDeg=70.0f;' 'if(fsrCameraFovDeg<10.0f||fsrCameraFovDeg>170.0f)fsrCameraFovDeg=45.0f;' 'FOV clamp fallback'
$vk=Once $vk 'const float fsrCameraNear=0.1f,fsrCameraFar=1000.0f,fsrCameraFovY=1.22173048f;' 'const float fsrCameraNear=0.05f,fsrCameraFar=1500.0f,fsrCameraFovY=0.7853981633974483f;' 'non-Vulkan defaults'

$oldLog=@'
            if(fsrProof)
                Log("M3K-FSR-P1: camera inputs are PROVISIONAL near=%.4f far=%.2f fovY=%.2fdeg; do not judge reconstruction quality until projection calibration is wired",
                    fsrCameraNear,fsrCameraFar,fsrCameraFovY*57.29577951308232f);
'@
$newLog=@'
            if(fsrProof)
                Log("M3K-FSR-P6: camera inputs CALIBRATED from GTA IV projection telemetry near=%.4f far=%.2f fovY=%.2fdeg depth=normal finite; INI overrides remain available",
                    fsrCameraNear,fsrCameraFar,fsrCameraFovY*57.29577951308232f);
'@
$vk=Once $vk $oldLog $newLog 'calibrated camera log'

foreach($marker in @(
    'g_m3kFsrCameraNear=0.05f',
    'g_m3kFsrCameraFar=1500.0f',
    'g_m3kFsrCameraFovY=0.7853981633974483f',
    'camera inputs CALIBRATED from GTA IV projection telemetry',
    'depth=normal finite'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR P6 verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
Write-Host 'FSR-P6 camera calibration applied: near=0.05 far=1500 fovY=45deg normal finite depth.'
