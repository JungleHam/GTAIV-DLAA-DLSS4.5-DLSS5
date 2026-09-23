[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR P9A stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
foreach($p in @($vkPath,$FeederSource)){if(-not(Test-Path -LiteralPath $p)){throw "Missing generated source: $p"}}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

$stateOld=@'
static bool g_m3kScalingTechnologyRestartPending=false;
static bool g_m3kScalingOffTransitionIssued=false;
static UINT g_m3kFsrScalePermille=667; // independent AMD/FSR scale; NVIDIA settings remain separate
'@
$stateNew=@'
static bool g_m3kScalingTechnologyRestartPending=false;
static bool g_m3kScalingOffTransitionIssued=false;
static UINT g_m3kScalingTransitionTarget=0xFFFFFFFFu; // P9A: 0=Off, 2=AMD, none=0xffffffff
static UINT g_m3kFsrScaleBeforeOff=667;
static UINT g_m3kFsrScalePermille=667; // independent AMD/FSR scale; NVIDIA settings remain separate
'@
$vk=Once $vk $stateOld $stateNew 'transition state'

$apiStart='static void M3kRequestScalingTechnologyRestart(UINT tech)'
$apiEnd='static UINT M3kFsrScalePermilleRequested(){return g_m3kFsrScalePermille;}'
$s=$vk.IndexOf($apiStart,[StringComparison]::Ordinal)
$e=$vk.IndexOf($apiEnd,$s,[StringComparison]::Ordinal)
if($s-lt 0-or$e-lt 0){throw 'P9A selector API span missing'}
$apiNew=@'
static bool M3kScalingNativeTransitionPending(){return g_m3kScalingTransitionTarget!=0xFFFFFFFFu;}
static void M3kInvalidateScalingPlan()
{
    g_m3kResolutionPlanProfile=0xFFFFFFFFu;
    g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;
    g_m3kResolutionConfirmedLogged=false;
    g_m3kFsrPlannerLogged=false;
    g_m3kFsrNeedsReset=true;
    g_m3kFsrLatchedFail=false;
    g_m3kFsrLastJitterEpoch=-1;
    g_m3k.ResetHistory();
}
static void M3kRequestScalingTechnologyLive(UINT tech)
{
    if(tech>2)tech=1;
    g_m3kScalingTechnologyRequested=tech;
    M3kWritePublicUInt(L"ScalingTechnology",tech);

    if(tech==g_m3kScalingTechnologyActive && !M3kScalingNativeTransitionPending()){
        g_m3kScalingTechnologyRestartPending=false;
        return;
    }

    const bool nativePair=
        g_m3kFsrNativeSession &&
        (g_m3kScalingTechnologyActive==0u||g_m3kScalingTechnologyActive==2u) &&
        (tech==0u||tech==2u);

    if(!nativePair){
        g_m3kScalingTechnologyRestartPending=true;
        Log("M3K-P9A: requested %s from %s; NVIDIA boundary remains restart-gated",
            M3kScalingTechnologyName(tech),M3kScalingTechnologyName(g_m3kScalingTechnologyActive));
        return;
    }

    g_m3kScalingTechnologyRestartPending=false;

    if(g_m3kScalingTechnologyActive==2u&&tech==0u){
        if(g_m3kScalingTransitionTarget==0u)return;
        g_m3kFsrScaleBeforeOff=g_m3kFsrScalePermille;
        g_m3kScalingTransitionTarget=0u;
        M3kInvalidateScalingPlan();
        M3kRequestMasterEnabledLive(false);
        Log("M3K-P9A: AMD -> Off stage 1; keeping FSR active while GTA returns to 100%% native, saved FSR scale=%.1f%%",
            static_cast<double>(g_m3kFsrScaleBeforeOff)/10.0);
        return;
    }

    if(g_m3kScalingTechnologyActive==0u&&tech==2u){
        g_m3kScalingTransitionTarget=2u;
        g_m3kScalingTechnologyActive=2u;
        g_m3kFsrScalePermille=g_m3kFsrScaleBeforeOff<100?667u:g_m3kFsrScaleBeforeOff;
        g_m3kFsrProofRequested=true;
        M3kInvalidateScalingPlan();
        M3kRequestMasterEnabledLive(true);
        g_m3kScalingTransitionTarget=0xFFFFFFFFu;
        Log("M3K-P9A: Off -> AMD LIVE committed in existing native Vulkan session; restored FSR scale=%.1f%%",
            static_cast<double>(g_m3kFsrScalePermille)/10.0);
        return;
    }
}
static void M3kAdvanceScalingTechnologyTransition()
{
    if(g_m3kScalingTransitionTarget!=0u)return;
    if(!M3kMasterNativePassthroughReady())return;

    g_m3kScalingTechnologyActive=0u;
    g_m3kFsrProofRequested=false;
    g_m3kFsrScalePermille=g_m3kFsrScaleBeforeOff;
    g_m3kScalingTransitionTarget=0xFFFFFFFFu;
    M3kInvalidateScalingPlan();
    Log("M3K-P9A: AMD -> Off LIVE COMMIT; raw native passthrough active, FSR dispatch stopped, native Vulkan session retained");
}

'@
$vk=$vk.Substring(0,$s)+$apiNew+$vk.Substring($e)

$pollScaleOld=@'
        if(fsrScalePermille<100)fsrScalePermille=100;
        if(fsrScalePermille>1000)fsrScalePermille=1000;
        float fsrSharpness=M3kReadPublicFloat(path,L"FSRSharpness",0.0f);
'@
$pollScaleNew=@'
        if(fsrScalePermille<100)fsrScalePermille=100;
        if(fsrScalePermille>1000)fsrScalePermille=1000;
        if(g_m3kScalingTransitionTarget==0u)fsrScalePermille=1000u;
        float fsrSharpness=M3kReadPublicFloat(path,L"FSRSharpness",0.0f);
'@
$vk=Once $vk $pollScaleOld $pollScaleNew 'temporary native FSR scale'

$pollStateOld=@'
        }else{
            g_m3kScalingTechnologyRequested=m3kTech;
            g_m3kScalingTechnologyRestartPending=
                g_m3kScalingTechnologyRequested!=g_m3kScalingTechnologyActive;
        }
'@
$pollStateNew=@'
        }else{
            g_m3kScalingTechnologyRequested=m3kTech;
            if(!M3kScalingNativeTransitionPending())
                g_m3kScalingTechnologyRestartPending=
                    g_m3kScalingTechnologyRequested!=g_m3kScalingTechnologyActive;
        }
'@
$vk=Once $vk $pollStateOld $pollStateNew 'transition-safe config poll'

$nativeReadyOld=@'
    const bool nativeReady = g_m3kSourceTapReady && g.width && g.height &&
        g_m3kSrProfileRequested == 0 && g_m3kSrProfileApplied == 0 &&
        g_m3kPresentSource.width == g.width && g_m3kPresentSource.height == g.height &&
        g_m3kPresentSource.presenterWidth == g.width && g_m3kPresentSource.presenterHeight == g.height;
'@
$nativeReadyNew=@'
    const bool p9aFsrOffTransition = g_m3kScalingTransitionTarget==0u && g_m3kFsrProofRequested;
    const bool nativeReady = g_m3kSourceTapReady && g.width && g.height &&
        (p9aFsrOffTransition || (g_m3kSrProfileRequested == 0 && g_m3kSrProfileApplied == 0)) &&
        g_m3kPresentSource.width == g.width && g_m3kPresentSource.height == g.height &&
        g_m3kPresentSource.presenterWidth == g.width && g_m3kPresentSource.presenterHeight == g.height;
'@
$vk=Once $vk $nativeReadyOld $nativeReadyNew 'FSR-aware native readiness'

$advanceOld='        M3kAdvanceMasterDisable();'
$advanceNew=@'
        M3kAdvanceMasterDisable();
        M3kAdvanceScalingTechnologyTransition();
'@
$feed=Once $feed $advanceOld $advanceNew 'per-frame transition advance'

$presentOld='    if (!M3kFsrSelectedAtSessionOpen() && g_cfg.mode >= 2 && g_cfg.vk_present_sync && !g_vk_present_sync_off && !FeedVkOrderPresent(rt, cl))'
$presentNew='    if (!g_m3kFsrNativeSession && g_cfg.mode >= 2 && g_cfg.vk_present_sync && !g_vk_present_sync_off && !FeedVkOrderPresent(rt, cl))'
$feed=Once $feed $presentOld $presentNew 'session-pinned Vulkan present gate'

$selectorOld='            M3kRequestScalingTechnologyRestart(static_cast<UINT>(technology));'
$selectorNew='            M3kRequestScalingTechnologyLive(static_cast<UINT>(technology));'
$feed=Once $feed $selectorOld $selectorNew 'live selector call'

$uiRestartOld=@'
        if(M3kScalingTechnologyRestartPending())
            ImGui::TextColored(ImVec4(1.0f,0.78f,0.25f,1.0f),
                "Restart GTA IV to switch to %s.",M3kScalingTechnologyName(M3kScalingTechnologyRequested()));
'@
$uiRestartNew=@'
        if(M3kScalingNativeTransitionPending())
            ImGui::TextColored(ImVec4(1.0f,0.78f,0.25f,1.0f),
                "Switching live: %s -> %s...",
                M3kScalingTechnologyName(M3kScalingTechnologyActive()),
                M3kScalingTechnologyName(M3kScalingTechnologyRequested()));
        else if(M3kScalingTechnologyRestartPending())
            ImGui::TextColored(ImVec4(1.0f,0.78f,0.25f,1.0f),
                "Restart GTA IV to cross the NVIDIA backend boundary in P9A.");
'@
$feed=Once $feed $uiRestartOld $uiRestartNew 'P9A selector status'

$rcasOld=@'
        Log("M3K-FSR-P1: FSR 3.1.4 Vulkan context READY max=%ux%u depthInverted=%d RCAS=OFF autoExposure=ON",
            finalW,finalH,inverted?1:0);
'@
$rcasNew=@'
        Log("M3K-FSR-P9A: FSR 3.1.4 Vulkan context READY max=%ux%u depthInverted=%d RCAS=%s sharpness=%.3f autoExposure=ON",
            finalW,finalH,inverted?1:0,g_m3kFsrSharpness>0.0001f?"ON":"OFF",
            static_cast<double>(g_m3kFsrSharpness));
'@
$vk=Once $vk $rcasOld $rcasNew 'RCAS context diagnostic'

foreach($marker in @(
    'M3K-P9A: AMD -> Off stage 1',
    'M3K-P9A: AMD -> Off LIVE COMMIT',
    'M3K-P9A: Off -> AMD LIVE committed',
    'M3kAdvanceScalingTechnologyTransition();',
    'if(g_m3kScalingTransitionTarget==0u)fsrScalePermille=1000u;',
    '!g_m3kFsrNativeSession && g_cfg.mode >= 2',
    'Restart GTA IV to cross the NVIDIA backend boundary in P9A.',
    'M3K-FSR-P9A: FSR 3.1.4 Vulkan context READY'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0 -and
       $feed.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR P9A verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'FSR-P9A live AMD<->Off transition stage applied.'
