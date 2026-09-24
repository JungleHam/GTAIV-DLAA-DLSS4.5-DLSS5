[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR P4A stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
foreach($p in @($vkPath,$FeederSource)){if(-not(Test-Path -LiteralPath $p)){throw "Missing generated source: $p"}}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

# P4A deliberately keeps the hardware-proven production b-bridge/jitter publisher
# unchanged. FidelityFX receives the exact pixel-space raster offset that GTA used.
# When no eligible projective scene draw was jittered (menus/loading), FSR still
# reconstructs the frame but history is reset every frame until raster jitter resumes.
$stateOld='static LONG g_m3kFsrLastJitterEpoch=-1;'
$stateNew=@'
static LONG g_m3kFsrLastJitterEpoch=-1;
static LONG g_m3kFsrLastJitterFrame=-1;
static bool g_m3kFsrJitterStateKnown=false;
static bool g_m3kFsrLastJitterActive=false;
'@
$vk=Once $vk $stateOld $stateNew 'FSR jitter state'

$resetStateOld='            g_m3kFsrNeedsReset=true;g_m3kFsrLatchedFail=false;g_m3kFsrLastJitterEpoch=-1;'
$resetStateNew=@'
            g_m3kFsrNeedsReset=true;g_m3kFsrLatchedFail=false;g_m3kFsrLastJitterEpoch=-1;
            g_m3kFsrLastJitterFrame=-1;g_m3kFsrJitterStateKnown=false;g_m3kFsrLastJitterActive=false;
'@
$vk=Once $vk $resetStateOld $resetStateNew 'selection resets jitter state'

$jitterOld=@'
    M3kBridgeJitterSnapshot jitter={};
    const bool jitterReadable=M3kReadBridgeJitter(&jitter);
    const bool jitterActive=jitterReadable&&jitter.valid&&jitter.active&&
        jitter.renderWidth==static_cast<LONG>(info.width)&&jitter.renderHeight==static_cast<LONG>(info.height);
    if(jitterActive&&jitter.epoch!=g_m3kFsrLastJitterEpoch){
        g_m3kFsrNeedsReset=true;g_m3kFsrLastJitterEpoch=jitter.epoch;
    }

    // Publish the preceding transfer writes to FSR's compute reads.
'@
$jitterNew=@'
    M3kBridgeJitterSnapshot jitter={};
    const bool jitterReadable=M3kReadBridgeJitter(&jitter);
    const bool jitterActive=jitterReadable&&jitter.valid&&jitter.active&&
        jitter.renderWidth==static_cast<UINT>(info.width)&&jitter.renderHeight==static_cast<UINT>(info.height);

    const bool jitterTransition=!g_m3kFsrJitterStateKnown||
        jitterActive!=g_m3kFsrLastJitterActive||
        (jitterActive&&jitter.epoch!=g_m3kFsrLastJitterEpoch)||
        (jitterActive&&g_m3kFsrLastJitterFrame>=0&&jitter.frame<g_m3kFsrLastJitterFrame);
    if(jitterTransition)g_m3kFsrNeedsReset=true;

    // Menus/loading may have no eligible projective world draw. Do NOT switch to the
    // raw nearest low-res diagnostic image (which enlarges GTA's pixel-sized UI).
    // Reconstruct with zero jitter and reset each such frame so no false temporal
    // history accumulates. Gameplay automatically transitions to exact raster jitter.
    if(!jitterActive)g_m3kFsrNeedsReset=true;

    // Publish the preceding transfer writes to FSR's compute reads.
'@
$vk=Once $vk $jitterOld $jitterNew 'exact raster jitter lifecycle'

$dispatchSuccessOld=@'
    g_m3kFsrNeedsReset=false;

    // Publish FSR compute writes to the transfer read used for the direct Vulkan copy home.
'@
$dispatchSuccessNew=@'
    g_m3kFsrNeedsReset=false;
    g_m3kFsrJitterStateKnown=true;
    g_m3kFsrLastJitterActive=jitterActive;
    g_m3kFsrLastJitterEpoch=jitterActive?jitter.epoch:-1;
    g_m3kFsrLastJitterFrame=jitterActive?jitter.frame:-1;

    // Publish FSR compute writes to the transfer read used for the direct Vulkan copy home.
'@
$vk=Once $vk $dispatchSuccessOld $dispatchSuccessNew 'successful jitter state commit'

$logOld=@'
    if(frames==1||(frames%300)==0)
        Log("M3K-FSR-P1: FSR DIRECT Vulkan frame=%llu %ux%u -> %ux%u reset=%d jitter=(%+.4f,%+.4f) mvScale=(1,1) dt=%.2fms",
            static_cast<unsigned long long>(frames),info.width,info.height,finalW,finalH,d.reset?1:0,
            d.jitterX,d.jitterY,d.frameTimeMs);
'@
$logNew=@'
    if(frames==1||(frames%300)==0){
        Log("M3K-FSR-P1: FSR DIRECT Vulkan frame=%llu %ux%u -> %ux%u reset=%d jitter=(%+.4f,%+.4f) mvScale=(1,1) dt=%.2fms",
            static_cast<unsigned long long>(frames),info.width,info.height,finalW,finalH,d.reset?1:0,
            d.jitterX,d.jitterY,d.frameTimeMs);
        Log("M3K-FSR-P4A: exact raster handoff active=%d readable=%d bridgeFrame=%ld epoch=%ld raster=(%+.6f,%+.6f) fsr=(%+.6f,%+.6f) reset=%d",
            jitterActive?1:0,jitterReadable?1:0,jitterActive?jitter.frame:-1,jitterActive?jitter.epoch:-1,
            jitterActive?jitter.jitterX:0.0f,jitterActive?jitter.jitterY:0.0f,
            d.jitterX,d.jitterY,d.reset?1:0);
    }
'@
$vk=Once $vk $logOld $logNew 'side-by-side raster/FSR jitter log'

# Keep P3's accurate native-session banner fix locally without requiring the failed P4 stage.
$bannerOld=@'
    Breadcrumb("opening the D3D12 session (Vulkan transport)");
    Log("################ feed: opening D3D12 session (Vulkan transport) ################");
    g_ngx_dying = false;
'@
$bannerNew=@'
    if(M3kFsrSelectedAtSessionOpen()){
        Breadcrumb("opening the native FSR Vulkan session");
        Log("################ feed: opening NATIVE FSR Vulkan session ################");
    }else{
        Breadcrumb("opening the D3D12 session (Vulkan transport)");
        Log("################ feed: opening D3D12 session (Vulkan transport) ################");
    }
    g_ngx_dying = false;
'@
$feed=Once $feed $bannerOld $bannerNew 'accurate native FSR session banner'

foreach($marker in @(
    'M3K-FSR-P4A: exact raster handoff active=',
    'if(!jitterActive)g_m3kFsrNeedsReset=true;',
    'opening NATIVE FSR Vulkan session'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0 -and
       $feed.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR P4A verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'FSR-P4A applied: production bridge preserved; exact raster jitter handed directly to FSR.'
