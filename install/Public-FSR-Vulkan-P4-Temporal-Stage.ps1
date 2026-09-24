[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR P4 stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
foreach($p in @($vkPath,$FeederSource)){if(-not(Test-Path -LiteralPath $p)){throw "Missing generated source: $p"}}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

# ---------------------------------------------------------------------------
# V2 bridge handoff. The paired P4 b-bridge client appends exact phase metadata
# and identifies whether the raster sequence is the protected DLSS sequence or
# AMD's FSR helper-compatible sequence.
# ---------------------------------------------------------------------------
$sharedOld=@'
struct M3kJitterSharedV1 {
    uint32_t magic;
    uint32_t version;
    volatile LONG writeSeq;
    LONG active;
    LONG frame;
    LONG epoch;
    LONG renderWidth;
    LONG renderHeight;
    float jitterX;
    float jitterY;
};
'@
$sharedNew=@'
struct M3kJitterSharedV1 {
    uint32_t magic;
    uint32_t version;
    volatile LONG writeSeq;
    LONG active;
    LONG frame;
    LONG epoch;
    LONG renderWidth;
    LONG renderHeight;
    float jitterX;
    float jitterY;
    LONG phase;
    LONG phaseCount;
    LONG sequenceKind; // 0=DLSS legacy; 1=AMD FSR helper-compatible
};
'@
$vk=Once $vk $sharedOld $sharedNew 'shared jitter V2 layout'

$snapOld=@'
    float jitterX = 0.0f;
    float jitterY = 0.0f;
};
'@
$snapNew=@'
    float jitterX = 0.0f;
    float jitterY = 0.0f;
    LONG phase = -1;
    LONG phaseCount = 0;
    LONG sequenceKind = 0;
};
'@
$vk=Once $vk $snapOld $snapNew 'snapshot V2 fields'

$vk=Once $vk 'static constexpr uint32_t kM3kJitterVersion = 1u;' 'static constexpr uint32_t kM3kJitterVersion = 2u;' 'jitter handoff version'
$vk=$vk.Replace('Local\\M3K_GTAIV_Jitter_v1','Local\\M3K_GTAIV_Jitter_v2')
if($vk.IndexOf('Local\\M3K_GTAIV_Jitter_v1',[StringComparison]::Ordinal)-ge 0){throw 'FSR P4: old jitter mapping name remains'}

$readOld=@'
        snap.jitterX = s->jitterX;
        snap.jitterY = s->jitterY;
        MemoryBarrier();
'@
$readNew=@'
        snap.jitterX = s->jitterX;
        snap.jitterY = s->jitterY;
        snap.phase = s->phase;
        snap.phaseCount = s->phaseCount;
        snap.sequenceKind = s->sequenceKind;
        MemoryBarrier();
'@
$vk=Once $vk $readOld $readNew 'read V2 temporal metadata'

# Track the FSR jitter contract independently from the old DLSS jitter state.
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
$vk=Once $vk $resetStateOld $resetStateNew 'selection resets FSR jitter contract'

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

    // FSR temporal accumulation is not allowed to start until the paired bridge proves
    // it actually rasterized this frame with the AMD sequence. Menus/resize churn can
    // temporarily have no eligible projective draw; show raw diagnostic output then.
    const bool fsrJitterContract=jitterActive&&jitter.sequenceKind==1&&
        jitter.phase>=0&&jitter.phaseCount>=2&&jitter.phase<jitter.phaseCount;
    if(!fsrJitterContract){
        static UINT64 waits=0;++waits;
        if(waits==1||(waits%300)==0)
            Log("M3K-FSR-P4: waiting for active AMD raster jitter (readable=%d valid=%d active=%d seq=%ld phase=%ld/%ld render=%ux%u); FSR NOT DISPATCHED",
                jitterReadable?1:0,jitter.valid?1:0,jitter.active?1:0,jitter.sequenceKind,
                jitter.phase,jitter.phaseCount,jitter.renderWidth,jitter.renderHeight);
        g_m3kFsrJitterStateKnown=false;
        g_m3kFsrLastJitterActive=false;
        return false;
    }

    float amdExpectedX=0.0f,amdExpectedY=0.0f;
    const FfxErrorCode jitterCode=ffxFsr3UpscalerGetJitterOffset(
        &amdExpectedX,&amdExpectedY,static_cast<int32_t>(jitter.phase),static_cast<int32_t>(jitter.phaseCount));
    const float jitterErrorX=fabsf(amdExpectedX-jitter.jitterX);
    const float jitterErrorY=fabsf(amdExpectedY-jitter.jitterY);
    const bool jitterMatch=jitterCode==FFX_OK&&jitterErrorX<0.00005f&&jitterErrorY<0.00005f;
    if(!jitterMatch){
        Log("M3K-FSR-P4: JITTER CONTRACT MISMATCH phase=%ld/%ld raster=(%+.6f,%+.6f) AMD=(%+.6f,%+.6f) err=(%.6f,%.6f) code=%d; FSR NOT DISPATCHED",
            jitter.phase,jitter.phaseCount,jitter.jitterX,jitter.jitterY,amdExpectedX,amdExpectedY,
            jitterErrorX,jitterErrorY,static_cast<int>(jitterCode));
        return false;
    }

    const bool jitterTransition=!g_m3kFsrJitterStateKnown||
        !g_m3kFsrLastJitterActive||jitter.epoch!=g_m3kFsrLastJitterEpoch||
        (g_m3kFsrLastJitterFrame>=0&&jitter.frame<g_m3kFsrLastJitterFrame);
    if(jitterTransition)g_m3kFsrNeedsReset=true;

    // Publish the preceding transfer writes to FSR's compute reads.
'@
$vk=Once $vk $jitterOld $jitterNew 'strict AMD jitter contract'

$dispatchSuccessOld=@'
    g_m3kFsrNeedsReset=false;

    // Publish FSR compute writes to the transfer read used for the direct Vulkan copy home.
'@
$dispatchSuccessNew=@'
    g_m3kFsrNeedsReset=false;
    g_m3kFsrJitterStateKnown=true;
    g_m3kFsrLastJitterActive=true;
    g_m3kFsrLastJitterEpoch=jitter.epoch;
    g_m3kFsrLastJitterFrame=jitter.frame;

    // Publish FSR compute writes to the transfer read used for the direct Vulkan copy home.
'@
$vk=Once $vk $dispatchSuccessOld $dispatchSuccessNew 'successful jitter-state commit'

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
        Log("M3K-FSR-P4: raster==FSR jitter MATCH bridgeFrame=%ld epoch=%ld phase=%ld/%ld raster=(%+.6f,%+.6f) AMD=(%+.6f,%+.6f) reset=%d",
            jitter.frame,jitter.epoch,jitter.phase,jitter.phaseCount,jitter.jitterX,jitter.jitterY,
            amdExpectedX,amdExpectedY,d.reset?1:0);
    }
'@
$vk=Once $vk $logOld $logNew 'P4 side-by-side temporal log'

# Remove the misleading legacy banner when P3/P4 selects native FSR.
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
$feed=Once $feed $bannerOld $bannerNew 'accurate FSR session banner'

foreach($marker in @(
    'Local\\M3K_GTAIV_Jitter_v2',
    'kM3kJitterVersion = 2u',
    'sequenceKind',
    'M3K-FSR-P4: waiting for active AMD raster jitter',
    'ffxFsr3UpscalerGetJitterOffset',
    'JITTER CONTRACT MISMATCH',
    'raster==FSR jitter MATCH',
    'opening NATIVE FSR Vulkan session'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0 -and
       $feed.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR P4 verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'FSR-P4 temporal stage applied: strict AMD jitter contract + V2 bridge handoff.'
