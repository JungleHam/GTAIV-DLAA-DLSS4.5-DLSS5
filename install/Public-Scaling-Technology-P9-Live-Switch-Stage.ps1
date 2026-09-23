[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR P9 stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}
function Replace-Function([string]$Text,[string]$Signature,[string]$New,[string]$Label){
    $start=$Text.IndexOf($Signature,[StringComparison]::Ordinal)
    if($start-lt 0){throw "FSR P9 stage \${Label}: function signature missing"}
    $brace=$Text.IndexOf('{',$start)
    if($brace-lt 0){throw "FSR P9 stage \${Label}: opening brace missing"}
    $depth=0;$end=-1
    for($i=$brace;$i-lt $Text.Length;$i++){
        if($Text[$i]-eq '{'){$depth++}
        elseif($Text[$i]-eq '}'){
            $depth--
            if($depth-eq 0){$end=$i+1;break}
        }
    }
    if($end-lt 0){throw "FSR P9 stage \${Label}: closing brace missing"}
    return $Text.Substring(0,$start)+$New+$Text.Substring($end)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
foreach($p in @($vkPath,$FeederSource)){if(-not(Test-Path -LiteralPath $p)){throw "Missing generated source: $p"}}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

$earlyOld=@'
static bool g_m3kFsrNativeSession=false;
static void M3kFsrNativeShutdownAfterQueueIdle();
static void ShutdownSession();   // defined below; every InitSession* unwinds through it
'@
$earlyNew=@'
static bool g_m3kFsrNativeSession=false;
static void M3kFsrNativeShutdownAfterQueueIdle();
static UINT M3kSessionBackendSelectionAtOpen();
static void M3kSetSessionBackendSelection(UINT tech);
static bool M3kCommitScalingTechnologyTransition();
static void ShutdownSession();   // defined below; every InitSession* unwinds through it
'@
$feed=Once $feed $earlyOld $earlyNew 'early live-switch declarations'

$sessionSelector=@'
static volatile LONG g_m3kSessionBackendSelection=-1;

static UINT M3kReadConfiguredScalingTechnologyAtSessionOpen()
{
    wchar_t path[MAX_PATH]={};
    if(!GetModuleFileNameW(g_self,path,MAX_PATH))return 1u;
    wchar_t *slash=wcsrchr(path,L'\\');
    if(!slash)return 1u;
    *(slash+1)=0;
    wcscat_s(path,L"m3k-nr.ini");

    wchar_t techText[16]={};
    GetPrivateProfileStringW(L"M3K",L"ScalingTechnology",L"",techText,16,path);
    if(techText[0]){
        wchar_t *end=nullptr;
        const unsigned long tech=wcstoul(techText,&end,10);
        if(end!=techText&&tech<=2ul)return static_cast<UINT>(tech);
    }
    return GetPrivateProfileIntW(L"M3K",L"FSRProof",0,path)!=0?2u:1u;
}

static UINT M3kSessionBackendSelectionAtOpen()
{
    LONG value=InterlockedCompareExchange(&g_m3kSessionBackendSelection,-1,-1);
    if(value>=0&&value<=2)return static_cast<UINT>(value);
    const UINT configured=M3kReadConfiguredScalingTechnologyAtSessionOpen();
    InterlockedCompareExchange(&g_m3kSessionBackendSelection,static_cast<LONG>(configured),-1);
    value=InterlockedCompareExchange(&g_m3kSessionBackendSelection,-1,-1);
    return value>=0&&value<=2?static_cast<UINT>(value):1u;
}

static void M3kSetSessionBackendSelection(UINT tech)
{
    if(tech>2)tech=1;
    InterlockedExchange(&g_m3kSessionBackendSelection,static_cast<LONG>(tech));
    Log("M3K-P9: session backend latch committed=%u",tech);
}

static bool M3kFsrSelectedAtSessionOpen()
{
    return M3kSessionBackendSelectionAtOpen()==2u;
}
'@
$feed=Replace-Function $feed 'static bool M3kFsrSelectedAtSessionOpen()' $sessionSelector 'session backend latch'

$stateOld=@'
static UINT g_m3kScalingTechnologyActive=1;    // 0 Off, 1 NVIDIA, 2 AMD
static UINT g_m3kScalingTechnologyRequested=1;
static bool g_m3kScalingTechnologyInitialized=false;
static bool g_m3kScalingTechnologyRestartPending=false;
static bool g_m3kScalingOffTransitionIssued=false;
'@
$stateNew=@'
static UINT g_m3kScalingTechnologyActive=1;    // 0 Off, 1 NVIDIA, 2 AMD
static UINT g_m3kScalingTechnologyRequested=1;
static bool g_m3kScalingTechnologyInitialized=false;
static bool g_m3kScalingTransitionPending=false;
static UINT g_m3kScalingTransitionTarget=1;
static bool g_m3kScalingTransitionNativeOverride=false;
static bool g_m3kScalingOffTransitionIssued=false;
static const char *M3kScalingTechnologyName(UINT tech);
static void M3kSetSessionBackendSelection(UINT tech);
static void ShutdownSession();
'@
$vk=Once $vk $stateOld $stateNew 'live-switch state'

$queryValid='    if (!renderW || !renderH || !targetW || !targetH) return false;'
$queryValidNew=@'
    if (!renderW || !renderH || !targetW || !targetH) return false;
    if(g_m3kScalingTechnologyActive==0u){
        *renderW=targetW;*renderH=targetH;
        return true;
    }
'@
$vk=Once $vk $queryValid $queryValidNew 'Off native planner'
$oldFsrP='        const UINT p=g_m3kFsrScalePermille<100?100:(g_m3kFsrScalePermille>1000?1000:g_m3kFsrScalePermille);'
$newFsrP='        const UINT p=g_m3kScalingTransitionNativeOverride?1000u:(g_m3kFsrScalePermille<100?100:(g_m3kFsrScalePermille>1000?1000:g_m3kFsrScalePermille));'
$vk=Once $vk $oldFsrP $newFsrP 'AMD native transition override'

$masterReady=@'
static bool M3kBackendNativeSourceReady()
{
    if(!g_m3kSourceTapReady||!g.width||!g.height)return false;
    const bool sourceNative=
        g_m3kPresentSource.width==g.width&&g_m3kPresentSource.height==g.height&&
        g_m3kPresentSource.presenterWidth==g.width&&g_m3kPresentSource.presenterHeight==g.height;
    if(!sourceNative)return false;
    if(g_m3kScalingTechnologyActive==0u)return true;
    if(g_m3kScalingTechnologyActive==2u)
        return g_m3kScalingTransitionNativeOverride&&
               g_m3kDesiredRenderW==g.width&&g_m3kDesiredRenderH==g.height;
    return g_m3kSrProfileRequested==0&&g_m3kSrProfileApplied==0;
}

static bool M3kMasterNativePassthroughReady()
{
    return !g_m3kMasterEnabled&&M3kBackendNativeSourceReady();
}
'@
$vk=Replace-Function $vk 'static bool M3kMasterNativePassthroughReady()' $masterReady 'backend-aware raw readiness'

$masterRequest=@'
static void M3kRequestMasterEnabledLive(bool enabled)
{
    if (!enabled)
    {
        if (!g_m3kMasterEnabled || g_m3kMasterDisablePending) return;

        M3kWriteMasterIni(L"MasterEnabled", 0);
        g_m3kMasterDisablePending = true;
        g_m3kMasterNativeStableFrames = 0;
        g_m3kMasterJitterOffTick = 0;

        if(g_m3kScalingTechnologyActive==1u)
        {
            UINT profile=M3kRequestedSrProfile();
            if(profile>6)profile=2;
            g_m3kMasterSavedProfile=profile;
            g_m3kMasterSavedNr=M3kNrEnabledRequested();
            M3kWriteMasterIni(L"LastSRProfile",g_m3kMasterSavedProfile);
            M3kWriteMasterIni(L"LastNRMode",g_m3kMasterSavedNr?2u:0u);
            M3kRequestNrEnabledLive(false);
            M3kRequestSrProfileLive(0);
            Log("M3K-P9: NVIDIA drain started through the proven DLAA Native path; saved NVIDIA profile=%s NR=%s",
                M3kSrProfileName(g_m3kMasterSavedProfile),g_m3kMasterSavedNr?"ON":"OFF");
        }
        else
        {
            Log("M3K-P9: %s drain started without modifying saved NVIDIA profile/NR state",
                M3kScalingTechnologyName(g_m3kScalingTechnologyActive));
        }

        g_m3k.ResetHistory();
        Log("M3K-MASTER-V2: OFF stage 1 - switching to native source; jitter stays ON during resize");
        return;
    }

    const bool wasPending=g_m3kMasterDisablePending;
    g_m3kMasterDisablePending=false;
    g_m3kMasterNativeStableFrames=0;
    g_m3kMasterJitterOffTick=0;
    g_m3kMasterEnabled=true;
    M3kWriteMasterIni(L"MasterEnabled",1);
    M3kWriteMasterIni(L"TemporalJitter",1);

    if(g_m3kScalingTechnologyActive==1u)
    {
        M3kRequestSrProfileLive(g_m3kMasterSavedProfile<=6?g_m3kMasterSavedProfile:2);
        M3kRequestNrEnabledLive(g_m3kMasterSavedNr);
        Log("M3K-P9: NVIDIA enabled%s; restored profile=%s NR=%s",
            wasPending?" after native drain":"",
            M3kSrProfileName(g_m3kMasterSavedProfile<=6?g_m3kMasterSavedProfile:2),
            g_m3kMasterSavedNr?"ON":"OFF");
    }
    else
    {
        Log("M3K-P9: %s enabled%s; NVIDIA profile/NR state left untouched",
            M3kScalingTechnologyName(g_m3kScalingTechnologyActive),
            wasPending?" after native drain":"");
    }
    g_m3k.ResetHistory();
}
'@
$vk=Replace-Function $vk 'static void M3kRequestMasterEnabledLive(bool enabled)' $masterRequest 'backend-aware master transition'

$advanceOld=@'
    const bool nativeReady = g_m3kSourceTapReady && g.width && g.height &&
        g_m3kSrProfileRequested == 0 && g_m3kSrProfileApplied == 0 &&
        g_m3kPresentSource.width == g.width && g_m3kPresentSource.height == g.height &&
        g_m3kPresentSource.presenterWidth == g.width && g_m3kPresentSource.presenterHeight == g.height;
'@
$advanceNew='    const bool nativeReady=M3kBackendNativeSourceReady();'
$vk=Once $vk $advanceOld $advanceNew 'backend-aware master native gate'

$selectorOldStart='static bool M3kScalingTechnologyRestartPending(){return g_m3kScalingTechnologyRestartPending;}'
$selectorOldEnd='static UINT M3kFsrScalePermilleRequested(){return g_m3kFsrScalePermille;}'
$selectorStart=$vk.IndexOf($selectorOldStart,[StringComparison]::Ordinal)
$selectorEnd=$vk.IndexOf($selectorOldEnd,$selectorStart,[StringComparison]::Ordinal)
if($selectorStart-lt 0 -or $selectorEnd-lt 0){throw 'FSR P9 selector API span missing'}
$selectorNew=@'
static bool M3kScalingTechnologyTransitionPending(){return g_m3kScalingTransitionPending;}
static UINT M3kScalingTechnologyTransitionTarget(){return g_m3kScalingTransitionTarget;}

static void M3kInvalidateBackendResolutionPlan()
{
    g_m3kResolutionPlanProfile=0xFFFFFFFFu;
    g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;
    g_m3kResolutionConfirmedLogged=false;
    g_m3kFsrPlannerLogged=false;
    g_m3kSrLatchedFail=false;
    g_m3kSrNeedsReset=true;
    g_m3kFsrLatchedFail=false;
    g_m3kFsrNeedsReset=true;
    g_m3kJitterEffectivePhases=0;
    g_m3k.ResetHistory();
}

static void M3kRequestScalingTechnologyLive(UINT tech)
{
    if(tech>2)tech=1;
    g_m3kScalingTechnologyRequested=tech;
    M3kWritePublicUInt(L"ScalingTechnology",tech);

    if(tech==g_m3kScalingTechnologyActive)
    {
        if(g_m3kScalingTransitionPending)
        {
            g_m3kScalingTransitionPending=false;
            g_m3kScalingTransitionTarget=tech;
            g_m3kScalingTransitionNativeOverride=false;
            M3kSetSessionBackendSelection(g_m3kScalingTechnologyActive);
            M3kInvalidateBackendResolutionPlan();
            if(g_m3kScalingTechnologyActive!=0u&&
               (!g_m3kMasterEnabled||g_m3kMasterDisablePending))
                M3kRequestMasterEnabledLive(true);
            Log("M3K-P9: backend switch cancelled; remaining on %s",
                M3kScalingTechnologyName(g_m3kScalingTechnologyActive));
        }
        return;
    }

    const bool wasPending=g_m3kScalingTransitionPending;
    g_m3kScalingTransitionPending=true;
    g_m3kScalingTransitionTarget=tech;
    g_m3kScalingTransitionNativeOverride=true;
    M3kInvalidateBackendResolutionPlan();

    if(g_m3kScalingTechnologyActive!=0u)
        M3kRequestMasterEnabledLive(false);

    Log("M3K-P9: live switch %s %s -> %s; draining through native/raw midpoint",
        wasPending?"retargeted":"requested",
        M3kScalingTechnologyName(g_m3kScalingTechnologyActive),
        M3kScalingTechnologyName(tech));
}

static bool M3kCommitScalingTechnologyTransition()
{
    if(!g_m3kScalingTransitionPending||!M3kMasterNativePassthroughReady())return false;

    const UINT oldTech=g_m3kScalingTechnologyActive;
    const UINT newTech=g_m3kScalingTransitionTarget<=2?g_m3kScalingTransitionTarget:1u;
    Log("M3K-P9: COMMIT begin %s -> %s at native %ux%u; old session teardown follows queue-idle safety",
        M3kScalingTechnologyName(oldTech),M3kScalingTechnologyName(newTech),g.width,g.height);

    if(g.session_ready)ShutdownSession();

    g_m3kScalingTechnologyActive=newTech;
    g_m3kScalingTechnologyRequested=newTech;
    M3kSetSessionBackendSelection(newTech);

    g_m3kFsrProofRequested=newTech==2u;
    g_m3kFsrLatchedFail=false;
    g_m3kFsrNeedsReset=true;
    g_m3kFsrLastJitterEpoch=-1;
    g_m3kFsrLastJitterFrame=-1;
    g_m3kFsrJitterStateKnown=false;
    g_m3kFsrLastJitterActive=false;
    g_m3kFsrLastQpc={};

    g_m3kSrRequested=false;
    g_m3kSrFeatureActive=false;
    g_m3kSrLatchedFail=false;
    g_m3kSrNeedsReset=true;
    g_m3kSrW=g_m3kSrH=g_m3kSrOutW=g_m3kSrOutH=0;
    g_m3kSrProfileApplied=0xFFFFFFFFu;

    g_m3kStartupPrimeActive=false;
    g_m3kStartupPrimeCompleted=true;
    g_m3kStartupPrimeConfigured=true;
    g_m3kStartupPrimeStableFrames=0;
    g_m3kStartupPrimeEpoch=-1;

    g_m3kScalingTransitionPending=false;
    g_m3kScalingTransitionTarget=newTech;
    g_m3kScalingTransitionNativeOverride=false;
    g_m3kScalingOffTransitionIssued=newTech==0u;
    M3kInvalidateBackendResolutionPlan();

    if(newTech==0u)
    {
        g_m3kMasterDisablePending=false;
        g_m3kMasterEnabled=false;
        g_m3kMasterNativeStableFrames=0;
        g_m3kMasterJitterOffTick=0;
        M3kWriteMasterIni(L"MasterEnabled",0);
        M3kWriteMasterIni(L"TemporalJitter",0);
    }
    else
    {
        M3kRequestMasterEnabledLive(true);
    }

    Log("M3K-P9: COMMIT complete active=%s; replacement backend opens on a later frame%s",
        M3kScalingTechnologyName(newTech),newTech==0u?" (Off stays sessionless/raw)":"");
    return true;
}

'@
$vk=$vk.Substring(0,$selectorStart)+$selectorNew+$vk.Substring($selectorEnd)

$initOld=@'
            g_m3kScalingTechnologyActive=m3kTech;
            g_m3kScalingTechnologyRequested=m3kTech;
            g_m3kScalingTechnologyRestartPending=false;
            g_m3kScalingTechnologyInitialized=true;
            g_m3kScalingOffTransitionIssued=false;
            Log("M3K-P7: active scaling technology captured at launch: %s",M3kScalingTechnologyName(m3kTech));
'@
$initNew=@'
            g_m3kScalingTechnologyActive=m3kTech;
            g_m3kScalingTechnologyRequested=m3kTech;
            g_m3kScalingTransitionPending=false;
            g_m3kScalingTransitionTarget=m3kTech;
            g_m3kScalingTransitionNativeOverride=false;
            g_m3kScalingTechnologyInitialized=true;
            g_m3kScalingOffTransitionIssued=false;
            M3kSetSessionBackendSelection(m3kTech);
            Log("M3K-P9: active scaling technology captured at launch: %s",M3kScalingTechnologyName(m3kTech));
'@
$vk=Once $vk $initOld $initNew 'launch backend capture'

$pollElseOld=@'
        }else{
            g_m3kScalingTechnologyRequested=m3kTech;
            g_m3kScalingTechnologyRestartPending=
                g_m3kScalingTechnologyRequested!=g_m3kScalingTechnologyActive;
        }
        if(g_m3kScalingTechnologyActive==0u&&!g_m3kScalingOffTransitionIssued&&M3kMasterEnabledRequested()){
            g_m3kScalingOffTransitionIssued=true;
            M3kRequestMasterEnabledLive(false);
            Log("M3K-P7: Off backend requested at launch; staged native raw transition started");
        }

'@
$pollElseNew=@'
        }else if(m3kTech!=g_m3kScalingTechnologyRequested){
            M3kRequestScalingTechnologyLive(m3kTech);
        }

'@
$vk=Once $vk $pollElseOld $pollElseNew 'poll follows live request state'

$offInsertOld=@'
            Log("M3K-MASTER-V2: session starts ON; master OFF is not carried across launches");
        }
        const UINT requested = g_m3kMasterEnabled ? GetPrivateProfileIntW(L"M3K", L"Mode", 0, path) : 0;
'@
$offInsertNew=@'
            Log("M3K-MASTER-V2: session starts ON; master OFF is not carried across launches");
        }
        if(g_m3kScalingTechnologyActive==0u&&!g_m3kScalingOffTransitionIssued&&M3kMasterEnabledRequested()){
            g_m3kScalingOffTransitionIssued=true;
            M3kRequestMasterEnabledLive(false);
            Log("M3K-P9: Off backend at launch; staged native raw transition started without opening NGX/FSR");
        }
        const UINT requested = g_m3kMasterEnabled ? GetPrivateProfileIntW(L"M3K", L"Mode", 0, path) : 0;
'@
$vk=Once $vk $offInsertOld $offInsertNew 'Off launch after master init'

$oldBanner='        Log("M3K-FSR-P1: FSR 3.1.4 Vulkan context READY max=%ux%u depthInverted=%d RCAS=OFF autoExposure=ON",'
$newBanner='        Log("M3K-FSR-P9: FSR 3.1.4 Vulkan context READY max=%ux%u depthInverted=%d RCAS=per-dispatch autoExposure=ON",'
$vk=Once $vk $oldBanner $newBanner 'RCAS context banner'

$rawOld=@'
        if (M3kMasterNativePassthroughReady())
        {
            if (!m3kMasterRawReported)
'@
$rawNew=@'
        if (M3kMasterNativePassthroughReady() && !M3kScalingTechnologyTransitionPending())
        {
            if (!m3kMasterRawReported)
'@
$feed=Once $feed $rawOld $rawNew 'allow serialized transition commit'

$frameAnchor=@'
    // Even a resource rebuild can flush the immediate list. Establish the game
'@
$frameInsert=@'
    if(M3kCommitScalingTechnologyTransition())
        return;

    const UINT m3kBackendAtFrame=M3kSessionBackendSelectionAtOpen();
    if(m3kBackendAtFrame==0u)
    {
        static bool m3kOffReported=false;
        if(!m3kOffReported){
            m3kOffReported=true;
            Log("M3K-P9: Off backend active - Vulkan frame passes untouched; no D3D12/NGX/FSR session is opened");
        }
        return;
    }

    // Even a resource rebuild can flush the immediate list. Establish the game
'@
$feed=Once $feed $frameAnchor $frameInsert 'serialized commit and Off session bypass'

$feed=$feed.Replace('M3kRequestScalingTechnologyRestart(static_cast<UINT>(technology))',
                    'M3kRequestScalingTechnologyLive(static_cast<UINT>(technology))')
$uiPendingOld=@'
        if(M3kScalingTechnologyRestartPending())
            ImGui::TextColored(ImVec4(1.0f,0.78f,0.25f,1.0f),
                "Restart GTA IV to switch to %s.",M3kScalingTechnologyName(M3kScalingTechnologyRequested()));

        const UINT activeTech=M3kScalingTechnologyActive();
'@
$uiPendingNew=@'
        if(M3kScalingTechnologyTransitionPending())
            ImGui::TextColored(ImVec4(1.0f,0.78f,0.25f,1.0f),
                "Switching to %s - returning GTA to native and draining temporal jitter...",
                M3kScalingTechnologyName(M3kScalingTechnologyTransitionTarget()));

        const UINT activeTech=M3kScalingTechnologyActive();
        const bool switching=M3kScalingTechnologyTransitionPending();
        if(switching)ImGui::BeginDisabled();
'@
$feed=Once $feed $uiPendingOld $uiPendingNew 'live switch UI status'

$diagAnchor='        if(ImGui::CollapsingHeader("Diagnostics##M3KDiagnostics")){'
$diagNew=@'
        if(switching)ImGui::EndDisabled();
        if(ImGui::CollapsingHeader("Diagnostics##M3KDiagnostics")){
'@
$feed=Once $feed $diagAnchor $diagNew 'transition control lock'

$diagOld='            ImGui::Text("Requested backend: %s",M3kScalingTechnologyName(M3kScalingTechnologyRequested()));'
$diagNew2=@'
            ImGui::Text("Requested backend: %s",M3kScalingTechnologyName(M3kScalingTechnologyRequested()));
            ImGui::Text("Backend transition: %s",M3kScalingTechnologyTransitionPending()?"native drain / commit pending":"idle");
'@
$feed=Once $feed $diagOld $diagNew2 'transition diagnostics'

foreach($marker in @(
    'M3K-P9: COMMIT begin',
    'M3K-P9: COMMIT complete',
    'M3K-P9: Off backend active - Vulkan frame passes untouched',
    'M3kSessionBackendSelectionAtOpen',
    'g_m3kScalingTransitionNativeOverride?1000u',
    'M3kScalingTechnologyTransitionPending',
    'M3kRequestScalingTechnologyLive',
    'RCAS=per-dispatch',
    'draining through native/raw midpoint',
    'without modifying saved NVIDIA profile/NR state'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0 -and
       $feed.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR P9 verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'FSR-P9 applied: transactional live Off/NVIDIA/AMD switching through native/raw midpoint.'
