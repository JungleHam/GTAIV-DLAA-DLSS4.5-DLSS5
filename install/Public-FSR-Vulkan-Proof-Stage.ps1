[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR proof stage ${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
if(-not(Test-Path -LiteralPath $vkPath)){throw "Missing generated source: $vkPath"}
if(-not(Test-Path -LiteralPath $FeederSource)){throw "Missing feeder source: $FeederSource"}
$backendSource=Join-Path $PSScriptRoot 'm3k_fsr_backend.h'
if(-not(Test-Path -LiteralPath $backendSource)){throw "Missing FSR backend: $backendSource"}
Copy-Item -LiteralPath $backendSource -Destination (Join-Path $GeneratedRoot 'm3k_fsr_backend.h') -Force

$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

$include=@'
#pragma once

// FSR-P1: hidden, opt-in Vulkan proof backend. When M3K/FSRProof=1 is selected,
// NGX/DLSS evaluation is forbidden for that frame; failures stay visibly on the FSR test path.
#include "m3k_fsr_backend.h"
'@
$vk=Once $vk '#pragma once' $include 'backend include'

$stateOld=@'
#if defined(VK_VERSION_1_0)
static bool g_m3kSrRequested = false;
'@
$stateNew=@'
#if defined(VK_VERSION_1_0)
static M3kFsrBackend g_m3kFsrBackend;
static bool g_m3kFsrProofRequested=false;
static bool g_m3kFsrLatchedFail=false;
static bool g_m3kFsrNeedsReset=true;
static LONG g_m3kFsrLastJitterEpoch=-1;
static float g_m3kFsrCameraNear=0.1f;
static float g_m3kFsrCameraFar=1000.0f;
static float g_m3kFsrCameraFovY=1.22173048f; // provisional 70 degrees; logged loudly
static LARGE_INTEGER g_m3kFsrLastQpc={};

static bool g_m3kSrRequested = false;
'@
$vk=Once $vk $stateOld $stateNew 'FSR state'

$pollOld=@'
        const bool srProof = GetPrivateProfileIntW(L"M3K", L"SRProof", 0, path) != 0;
'@
$pollNew=@'
        const bool srProof = GetPrivateProfileIntW(L"M3K", L"SRProof", 0, path) != 0;
        const bool fsrProof = GetPrivateProfileIntW(L"M3K", L"FSRProof", 0, path) != 0;
        auto m3kFsrReadFloat=[&](const wchar_t *key,float fallback){
            wchar_t value[64]={}; wchar_t def[64]={};
            _snwprintf_s(def,_TRUNCATE,L"%.6f",static_cast<double>(fallback));
            GetPrivateProfileStringW(L"M3K",key,def,value,64,path);
            wchar_t *end=nullptr; const double parsed=wcstod(value,&end);
            return end!=value?static_cast<float>(parsed):fallback;
        };
        const float fsrCameraNear=m3kFsrReadFloat(L"FSRCameraNear",0.1f);
        const float fsrCameraFar=m3kFsrReadFloat(L"FSRCameraFar",1000.0f);
        float fsrCameraFovDeg=m3kFsrReadFloat(L"FSRCameraFovYDegrees",70.0f);
        if(fsrCameraFovDeg<10.0f||fsrCameraFovDeg>170.0f)fsrCameraFovDeg=70.0f;
        const float fsrCameraFovY=fsrCameraFovDeg*0.01745329251994329577f;
'@
$vk=Once $vk $pollOld $pollNew 'INI FSR proof read'

$pollElseOld=@'
        const bool srProof = false;
'@
$pollElseNew=@'
        const bool srProof = false;
        const bool fsrProof = false;
        const float fsrCameraNear=0.1f,fsrCameraFar=1000.0f,fsrCameraFovY=1.22173048f;
'@
$vk=Once $vk $pollElseOld $pollElseNew 'non-Vulkan FSR defaults'

$assignOld=@'
        g_m3kSrRequested = srProof;
#endif
'@
$assignNew=@'
        g_m3kSrRequested = srProof;
        static bool fsrFirst=true;
        if(fsrFirst||fsrProof!=g_m3kFsrProofRequested){
            Log("M3K-FSR-P1: FSRProof=%d (isolated Vulkan proof; NGX/DLSS fallback FORBIDDEN while selected)",fsrProof?1:0);
            if(fsrProof)
                Log("M3K-FSR-P1: camera inputs are PROVISIONAL near=%.4f far=%.2f fovY=%.2fdeg; do not judge reconstruction quality until projection calibration is wired",
                    fsrCameraNear,fsrCameraFar,fsrCameraFovY*57.29577951308232f);
            g_m3kFsrNeedsReset=true;g_m3kFsrLatchedFail=false;g_m3kFsrLastJitterEpoch=-1;
            fsrFirst=false;
        }
        if(fsrCameraNear!=g_m3kFsrCameraNear||fsrCameraFar!=g_m3kFsrCameraFar||fsrCameraFovY!=g_m3kFsrCameraFovY){
            g_m3kFsrCameraNear=fsrCameraNear;g_m3kFsrCameraFar=fsrCameraFar;g_m3kFsrCameraFovY=fsrCameraFovY;
            g_m3kFsrNeedsReset=true;
        }
        g_m3kFsrProofRequested=fsrProof;
#endif
'@
$vk=Once $vk $assignOld $assignNew 'FSR proof state poll'

$prepareMarker='static void M3kPrepareFrame()'
$prepareAt=$vk.IndexOf($prepareMarker,[StringComparison]::Ordinal)
if($prepareAt-lt 0){throw 'M3kPrepareFrame marker missing'}
$helpers=@'
#if defined(VK_VERSION_1_0)
static void M3kFsrMessage(FfxMsgType type,const wchar_t *message)
{
    Log("M3K-FSR-DEBUG: type=%u %ls",static_cast<unsigned>(type),message?message:L"(null)");
}

static float M3kFsrFrameTimeMs()
{
    LARGE_INTEGER now={},freq={};QueryPerformanceCounter(&now);QueryPerformanceFrequency(&freq);
    float ms=16.6667f;
    if(g_m3kFsrLastQpc.QuadPart!=0&&freq.QuadPart>0){
        const double dt=static_cast<double>(now.QuadPart-g_m3kFsrLastQpc.QuadPart)*1000.0/static_cast<double>(freq.QuadPart);
        if(dt>=1.0&&dt<=250.0)ms=static_cast<float>(dt);
    }
    g_m3kFsrLastQpc=now;return ms;
}

// P1 deliberately reuses the already-proven DLSS SR resolution split and imported
// VkImages. DLSS is NOT evaluated when this succeeds; it merely remains the temporary
// owner of the resolution-planning machinery. P2 will separate that planner completely.
static bool M3kFsrTryDispatchVk(VkCommandBuffer cb,VkImage backbuffer,UINT finalW,UINT finalH,int reset)
{
    if(!g_m3kFsrProofRequested||g_m3kFsrLatchedFail)return false;
    if(!g_m3kSrFeatureActive||!g_m3kSourceTapReady||!g.vk.ok||cb==VK_NULL_HANDLE||backbuffer==VK_NULL_HANDLE)return false;
    if(g.vk.phys==VK_NULL_HANDLE||g.vk.GetDeviceProcAddr==nullptr){
        static bool said=false;if(!said){said=true;Log("M3K-FSR-P1: blocked: Feeder did not capture VkPhysicalDevice/GetDeviceProcAddr");}
        return false;
    }
    const auto info=g_m3kPresentSource;
    if(info.width!=g_m3kSrW||info.height!=g_m3kSrH||finalW!=g_m3kSrOutW||finalH!=g_m3kSrOutH)return false;
    if(g.vk_img[SLOT_COLOR]==VK_NULL_HANDLE||g.vk_img[SLOT_DEPTH]==VK_NULL_HANDLE||
       g.vk_img[SLOT_MV]==VK_NULL_HANDLE||g.vk_img[SLOT_OUTPUT]==VK_NULL_HANDLE)return false;

    const bool inverted=g_cfg.depth_inverted>=0?g_cfg.depth_inverted!=0:g.depth_reversed;
    if(!g_m3kFsrBackend.IsReady()){
        if(!g_m3kFsrBackend.Init(g.vk.dev,g.vk.phys,g.vk.GetDeviceProcAddr,
                                 finalW,finalH,finalW,finalH,inverted,false,M3kFsrMessage)){
            g_m3kFsrLatchedFail=true;
            Log("M3K-FSR-P1: context creation FAILED; proof latched failed; NGX fallback remains forbidden");
            return false;
        }
        g_m3kFsrNeedsReset=true;
        Log("M3K-FSR-P1: FSR 3.1.4 Vulkan context READY max=%ux%u depthInverted=%d RCAS=OFF autoExposure=ON",
            finalW,finalH,inverted?1:0);
    }else if(!g_m3kFsrBackend.Matches(g.vk.dev,g.vk.phys,finalW,finalH,finalW,finalH,inverted,false)){
        // P1 never destroys an FSR context during ReShade/device churn. That lifecycle
        // is intentionally deferred to P2's proven quarantine path.
        g_m3kFsrLatchedFail=true;
        Log("M3K-FSR-P1: device/output/depth contract changed; refusing unsafe in-flight context rebuild; NGX fallback forbidden");
        return false;
    }

    M3kBridgeJitterSnapshot jitter={};
    const bool jitterReadable=M3kReadBridgeJitter(&jitter);
    const bool jitterActive=jitterReadable&&jitter.valid&&jitter.active&&
        jitter.renderWidth==static_cast<LONG>(info.width)&&jitter.renderHeight==static_cast<LONG>(info.height);
    if(jitterActive&&jitter.epoch!=g_m3kFsrLastJitterEpoch){
        g_m3kFsrNeedsReset=true;g_m3kFsrLastJitterEpoch=jitter.epoch;
    }

    // Publish the preceding transfer writes to FSR's compute reads.
    const VkImage inputs[4]={g.vk_img[SLOT_COLOR],g.vk_img[SLOT_DEPTH],g.vk_img[SLOT_MV],g.vk_img[SLOT_OUTPUT]};
    FeedVkBarrierN(&g.vk,cb,inputs,4,VK_IMAGE_LAYOUT_GENERAL,VK_IMAGE_LAYOUT_GENERAL);

    M3kFsrDispatchInputs d={};
    d.commandBuffer=cb;
    // Imported Feeder images are native-sized allocations; only the top-left render
    // subrect contains the low-resolution color/depth/MV captured by M3kSrCaptureVk.
    d.color={g.vk_img[SLOT_COLOR],FeedVkFormat(g.color_fmt),finalW,finalH,false};
    d.depth={g.vk_img[SLOT_DEPTH],VK_FORMAT_R32_SFLOAT,finalW,finalH,false};
    d.motionVectors={g.vk_img[SLOT_MV],VK_FORMAT_R16G16_SFLOAT,finalW,finalH,false};
    d.output={g.vk_img[SLOT_OUTPUT],FeedVkFormat(g.output_fmt),finalW,finalH,true};
    d.renderWidth=info.width;d.renderHeight=info.height;
    d.outputWidth=finalW;d.outputHeight=finalH;
    // The bridge publishes the exact pixel-space sample used by GTA's projection.
    // Unlike NGX, no NVIDIA-specific compensation is applied here.
    d.jitterX=jitterActive?jitter.jitterX:0.0f;
    d.jitterY=jitterActive?jitter.jitterY:0.0f;
    // Lumenite's provider is configured to emit pixel-space vectors; P1 keeps the
    // conversion scale at 1 and logs it as a hardware-validation item.
    d.motionVectorScaleX=1.0f;d.motionVectorScaleY=1.0f;
    d.frameTimeMs=M3kFsrFrameTimeMs();
    d.preExposure=1.0f;
    d.reset=reset!=0||g_m3kFsrNeedsReset;
    d.cameraNear=g_m3kFsrCameraNear;d.cameraFar=g_m3kFsrCameraFar;
    d.cameraFovAngleVertical=g_m3kFsrCameraFovY;d.viewSpaceToMetersFactor=1.0f;

    if(!g_m3kFsrBackend.Dispatch(d)){
        g_m3kFsrLatchedFail=true;g_m3kFsrNeedsReset=true;
        Log("M3K-FSR-P1: dispatch FAILED; proof latched failed; NGX fallback forbidden");
        return false;
    }
    g_m3kFsrNeedsReset=false;

    // Publish FSR compute writes to the transfer read used for the direct Vulkan copy home.
    FeedVkBarrier(&g.vk,cb,g.vk_img[SLOT_OUTPUT],VK_IMAGE_LAYOUT_GENERAL,VK_IMAGE_LAYOUT_GENERAL);
    if(SameTexelLayout(g.output_fmt,g.bb_fmt))
        FeedVkCopyImage(&g.vk,cb,g.vk_img[SLOT_OUTPUT],VK_IMAGE_LAYOUT_GENERAL,
                        backbuffer,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,finalW,finalH);
    else
        FeedVkBlitImage(&g.vk,cb,g.vk_img[SLOT_OUTPUT],VK_IMAGE_LAYOUT_GENERAL,
                        backbuffer,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,finalW,finalH);

    static UINT64 frames=0;++frames;
    if(frames==1||(frames%300)==0)
        Log("M3K-FSR-P1: FSR DIRECT Vulkan frame=%llu %ux%u -> %ux%u reset=%d jitter=(%+.4f,%+.4f) mvScale=(1,1) dt=%.2fms",
            static_cast<unsigned long long>(frames),info.width,info.height,finalW,finalH,d.reset?1:0,
            d.jitterX,d.jitterY,d.frameTimeMs);
    return true;
}
#endif

'@
$vk=$vk.Substring(0,$prepareAt)+$helpers+$vk.Substring($prepareAt)

# Insert the direct Vulkan branch after the normal path has parked the game's
# backbuffer as TRANSFER_DST and calculated this frame's reset, but BEFORE any
# imported resource is released to the D3D12/NGX side.
$frameMarker='            const UINT64 n = ++g.vk_frame;'
$frameAt=$feed.IndexOf($frameMarker,[StringComparison]::Ordinal)
if($frameAt-lt 0){throw 'Vulkan frame counter marker missing'}
$resetMarker='            g.need_reset = false;'
$resetAt=$feed.IndexOf($resetMarker,$frameAt,[StringComparison]::Ordinal)
if($resetAt-lt 0-or $resetAt-$frameAt-gt 1000){throw 'Vulkan reset marker missing near frame counter'}
$insertAt=$resetAt+$resetMarker.Length
$direct=@'

            // FSR-P1 is an isolated backend selection. Once requested, this frame is
            // NEVER allowed to fall through into the D3D12/NGX DLSS path.
            if(g_m3kFsrProofRequested)
            {
                const bool fsrDelivered=M3kFsrTryDispatchVk(cb,bb_img,w,h,reset);
                if(!fsrDelivered)
                {
                    // Make failure visible without invoking NVIDIA reconstruction:
                    // nearest-blit the real DXVK source directly to the presenter.
                    const auto fsrInfo=g_m3kPresentSource;
                    const VkImage fsrSource=FeedVkHandle<VkImage>(fsrInfo.image);
                    const VkImageLayout fsrSourceLayout=static_cast<VkImageLayout>(fsrInfo.layout);
                    if(g_m3kSourceTapReady&&fsrSource!=VK_NULL_HANDLE&&
                       (fsrSourceLayout==VK_IMAGE_LAYOUT_GENERAL||fsrSourceLayout==VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)&&
                       fsrInfo.width&&fsrInfo.height)
                    {
                        FeedVkBarrier(&g.vk,cb,fsrSource,fsrSourceLayout,fsrSourceLayout);
                        M3kVkBlitScale(cb,fsrSource,fsrSourceLayout,bb_img,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                       fsrInfo.width,fsrInfo.height,w,h);
                        static UINT64 fsrFailFrames=0;++fsrFailFrames;
                        if(fsrFailFrames==1||(fsrFailFrames%300)==0)
                            Log("M3K-FSR-P1: FSR unavailable/failed; showing raw nearest DXVK source %ux%u -> %ux%u; NGX NOT RUN",
                                fsrInfo.width,fsrInfo.height,w,h);
                    }
                    else
                    {
                        static bool fsrNoSourceLogged=false;
                        if(!fsrNoSourceLogged){fsrNoSourceLogged=true;Log("M3K-FSR-P1: FSR failed and raw DXVK diagnostic source unavailable; NGX NOT RUN");}
                    }
                }

                const resource res[1]={bb_res};
                const resource_usage from[1]={resource_usage::copy_dest};
                const resource_usage to[1]={resource_usage::render_target};
                cl->barrier(1,res,from,to);
                const UINT64 fn=++g.frames_done;
                g.consecutive_fails=fsrDelivered?0:(g.consecutive_fails+1);
                if(fsrDelivered&&(fn<=static_cast<UINT64>(g_cfg.log_frames)||(fn%1800)==0))
                    Log("[feed] frame %llu delivered by FSR 3.1.4 DIRECT Vulkan proof (%ux%u)",
                        static_cast<unsigned long long>(fn),w,h);
                QueryPerformanceCounter(&t1);
                TimingTick(t0.QuadPart,t1.QuadPart);
                return;
            }
'@
$feed=$feed.Substring(0,$insertAt)+$direct+$feed.Substring($insertAt)

foreach($marker in @(
    '#include "m3k_fsr_backend.h"',
    'M3kFsrTryDispatchVk',
    'FSRProof',
    'FSRCameraFovYDegrees',
    'delivered by FSR 3.1.4 DIRECT Vulkan proof'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0 -and
       $feed.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR proof marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host "FSR-P1 hidden Vulkan proof stage applied."
