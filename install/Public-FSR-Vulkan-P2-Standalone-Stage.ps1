[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR P2 stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
if(-not(Test-Path -LiteralPath $vkPath)){throw "Missing generated source: $vkPath"}
if(-not(Test-Path -LiteralPath $FeederSource)){throw "Missing feeder source: $FeederSource"}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

# P2 separates FSR's render-size plan from NVIDIA SR profile/capability queries.
$stateOld='static LARGE_INTEGER g_m3kFsrLastQpc={};'
$stateNew=@'
static LARGE_INTEGER g_m3kFsrLastQpc={};
static UINT g_m3kFsrScalePermille=667; // P2 fixed FSR Quality ~= 2/3 input scale
static bool g_m3kFsrPlannerLogged=false;
'@
$vk=Once $vk $stateOld $stateNew 'FSR P2 state'

$pollOld='        const float fsrCameraFovY=fsrCameraFovDeg*0.01745329251994329577f;'
$pollNew=@'
        const float fsrCameraFovY=fsrCameraFovDeg*0.01745329251994329577f;
        UINT fsrScalePermille=GetPrivateProfileIntW(L"M3K",L"FSRScalePermille",667,path);
        if(fsrScalePermille<100)fsrScalePermille=100;
        if(fsrScalePermille>1000)fsrScalePermille=1000;
'@
$vk=Once $vk $pollOld $pollNew 'FSR scale read'

$nonVkOld='        const float fsrCameraNear=0.1f,fsrCameraFar=1000.0f,fsrCameraFovY=1.22173048f;'
$nonVkNew=@'
        const float fsrCameraNear=0.1f,fsrCameraFar=1000.0f,fsrCameraFovY=1.22173048f;
        const UINT fsrScalePermille=667u;
'@
$vk=Once $vk $nonVkOld $nonVkNew 'non-Vulkan FSR scale default'

$changeOld='            g_m3kFsrNeedsReset=true;g_m3kFsrLatchedFail=false;g_m3kFsrLastJitterEpoch=-1;'
$changeNew=@'
            g_m3kFsrNeedsReset=true;g_m3kFsrLatchedFail=false;g_m3kFsrLastJitterEpoch=-1;
            g_m3kResolutionPlanProfile=0xFFFFFFFFu;g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;
            g_m3kResolutionConfirmedLogged=false;g_m3kFsrPlannerLogged=false;
'@
$vk=Once $vk $changeOld $changeNew 'backend selection invalidates plan'

$assignOld=@'
        g_m3kFsrProofRequested=fsrProof;
#endif
'@
$assignNew=@'
        if(fsrScalePermille!=g_m3kFsrScalePermille){
            g_m3kFsrScalePermille=fsrScalePermille;
            g_m3kResolutionPlanProfile=0xFFFFFFFFu;g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;
            g_m3kResolutionConfirmedLogged=false;g_m3kFsrPlannerLogged=false;g_m3kFsrNeedsReset=true;
            Log("M3K-FSR-P2: independent FSR scale changed to %.1f%%; render plan invalidated",
                static_cast<double>(g_m3kFsrScalePermille)/10.0);
        }
        g_m3kFsrProofRequested=fsrProof;
#endif
'@
$vk=Once $vk $assignOld $assignNew 'FSR P2 scale commit'

# FSR owns its render-size plan; do not arm the DLSS cold-start prime while FSR is selected.
$primeOld='    if (g_m3kStartupPrimeConfigured) return;'
$primeNew=@'
    if(g_m3kFsrProofRequested){
        if(g_m3kStartupPrimeActive){
            g_m3kStartupPrimeActive=false;g_m3kStartupPrimeCompleted=true;
            g_m3kStartupPrimeStableFrames=0;g_m3kStartupPrimeEpoch=-1;
        }
        static bool fsrPrimeLogged=false;
        if(!fsrPrimeLogged){fsrPrimeLogged=true;Log("M3K-FSR-P2: DLSS startup prime BYPASSED for FSR backend");}
        return;
    }
    if (g_m3kStartupPrimeConfigured) return;
'@
$vk=Once $vk $primeOld $primeNew 'startup prime bypass'

# Put the FSR branch at the very top of the shared resolution query so no NGX
# capability query or DLSS profile contract is involved.
$queryFn='static bool M3kQueryProfileRenderSize(UINT profile, UINT targetW, UINT targetH, UINT *renderW, UINT *renderH)'
$queryAt=$vk.IndexOf($queryFn,[StringComparison]::Ordinal)
if($queryAt-lt 0){throw 'FSR P2: render-size query missing'}
$valid='    if (!renderW || !renderH || !targetW || !targetH) return false;'
$validAt=$vk.IndexOf($valid,$queryAt,[StringComparison]::Ordinal)
if($validAt-lt 0){throw 'FSR P2: render-size validity line missing'}
$insertAt=$validAt+$valid.Length
$queryInsert=@'

    if(g_m3kFsrProofRequested){
        const UINT p=g_m3kFsrScalePermille<100?100:(g_m3kFsrScalePermille>1000?1000:g_m3kFsrScalePermille);
        *renderW=(targetW*p+500u)/1000u;
        *renderH=(targetH*p+500u)/1000u;
        if(!*renderW||!*renderH)return false;

        const int32_t phaseRaw=ffxFsr3UpscalerGetJitterPhaseCount(
            static_cast<int32_t>(*renderW),static_cast<int32_t>(targetW));
        const UINT phaseCount=phaseRaw<2?2u:static_cast<UINT>(phaseRaw);
        if(g_m3kJitterEffectivePhases!=phaseCount){
            g_m3kJitterEffectivePhases=phaseCount;
            wchar_t fsrPath[MAX_PATH]={};
            if(GetModuleFileNameW(g_self,fsrPath,MAX_PATH)){
                if(wchar_t *s=wcsrchr(fsrPath,L'\\')){
                    *(s+1)=0;wcscat_s(fsrPath,L"m3k-nr.ini");
                    wchar_t phaseText[16]={};_snwprintf_s(phaseText,_TRUNCATE,L"%u",phaseCount);
                    WritePrivateProfileStringW(L"M3K",L"JitterPhases",phaseText,fsrPath);
                }
            }
            Log("M3K-FSR-P2: AMD jitter phase count=%u for %ux%u -> %ux%u; bridge config updated",
                phaseCount,*renderW,*renderH,targetW,targetH);
        }
        if(!g_m3kFsrPlannerLogged){
            g_m3kFsrPlannerLogged=true;
            Log("M3K-FSR-P2: independent FSR render planner %.1f%% -> %ux%u for output %ux%u (no NGX size query)",
                static_cast<double>(p)/10.0,*renderW,*renderH,targetW,targetH);
        }
        return true;
    }
'@
$vk=$vk.Substring(0,$insertAt)+$queryInsert+$vk.Substring($insertAt)

# FSR path does not create/swap a DLSS SR feature. The baseline Feeder resource
# allocation is still present in P2; removing that remaining NGX bootstrap is P3.
$srFn='static void M3kSrUpdate()'
$srAt=$vk.IndexOf($srFn,[StringComparison]::Ordinal)
if($srAt-lt 0){throw 'FSR P2: M3kSrUpdate missing'}
$brace=$vk.IndexOf('{',$srAt,[StringComparison]::Ordinal)
$srEarly=@'

    if(g_m3kFsrProofRequested){
        // FSR has its own resolution plan. Never create/swap a DLSS SR feature.
        return;
    }
'@
$vk=$vk.Substring(0,$brace+1)+$srEarly+$vk.Substring($brace+1)

# Capture the real low-resolution color and scaled temporal guides for either backend.
$captureOld=@'
    if (!g_m3kSrFeatureActive || !g_m3kSourceTapReady || cb == VK_NULL_HANDLE)
        return;
    const auto info = g_m3kPresentSource;
    if (info.width != g_m3kSrW || info.height != g_m3kSrH ||
        finalW != g_m3kSrOutW || finalH != g_m3kSrOutH)
        return;
'@
$captureNew=@'
    if ((!g_m3kSrFeatureActive && !g_m3kFsrProofRequested) || !g_m3kSourceTapReady || cb == VK_NULL_HANDLE)
        return;
    const auto info = g_m3kPresentSource;
    const UINT expectedW=g_m3kFsrProofRequested?g_m3kDesiredRenderW:g_m3kSrW;
    const UINT expectedH=g_m3kFsrProofRequested?g_m3kDesiredRenderH:g_m3kSrH;
    const UINT expectedOutW=g_m3kFsrProofRequested?g.width:g_m3kSrOutW;
    const UINT expectedOutH=g_m3kFsrProofRequested?g.height:g_m3kSrOutH;
    if (info.width != expectedW || info.height != expectedH ||
        finalW != expectedOutW || finalH != expectedOutH)
        return;
'@
$vk=Once $vk $captureOld $captureNew 'backend-neutral temporal capture'

$dispatchGateOld='    if(!g_m3kSrFeatureActive||!g_m3kSourceTapReady||!g.vk.ok||cb==VK_NULL_HANDLE||backbuffer==VK_NULL_HANDLE)return false;'
$dispatchGateNew='    if(!g_m3kSourceTapReady||!g.vk.ok||cb==VK_NULL_HANDLE||backbuffer==VK_NULL_HANDLE)return false;'
$vk=Once $vk $dispatchGateOld $dispatchGateNew 'remove DLSS SR active requirement'

$sizeOld='    if(info.width!=g_m3kSrW||info.height!=g_m3kSrH||finalW!=g_m3kSrOutW||finalH!=g_m3kSrOutH)return false;'
$sizeNew=@'
    if(!g_m3kDesiredRenderW||!g_m3kDesiredRenderH)return false;
    if(info.width!=g_m3kDesiredRenderW||info.height!=g_m3kDesiredRenderH||finalW!=g.width||finalH!=g.height)return false;
'@
$vk=Once $vk $sizeOld $sizeNew 'FSR independent size gate'

# Auto jitter phase count follows AMD's exact helper while FSR is selected instead
# of the DLSS-oriented ceil formula.
$phaseOld=@'
static UINT M3kComputeAutoJitterPhases(){
    UINT rw=0,rh=0;const UINT profile=M3kRequestedSrProfile();
'@
$phaseNew=@'
static UINT M3kComputeAutoJitterPhases(){
    if(g_m3kFsrProofRequested&&g.width&&g_m3kDesiredRenderW){
        const int32_t fsrPhases=ffxFsr3UpscalerGetJitterPhaseCount(
            static_cast<int32_t>(g_m3kDesiredRenderW),static_cast<int32_t>(g.width));
        return fsrPhases<2?2u:static_cast<UINT>(fsrPhases);
    }
    UINT rw=0,rh=0;const UINT profile=M3kRequestedSrProfile();
'@
$vk=Once $vk $phaseOld $phaseNew 'FSR SDK jitter phase count'

# Periodically include enough P2 state in the existing direct-dispatch log.
$logOld='            d.jitterX,d.jitterY,d.frameTimeMs);'
$logNew=@'
            d.jitterX,d.jitterY,d.frameTimeMs);
    if(frames==1||(frames%1800)==0)
        Log("M3K-FSR-P2: isolated planner source=%ux%u output=%ux%u scale=%.1f%% phases=%u SRProof=%d startupPrime=%d",
            g_m3kDesiredRenderW,g_m3kDesiredRenderH,g.width,g.height,
            static_cast<double>(g_m3kFsrScalePermille)/10.0,M3kComputeAutoJitterPhases(),
            g_m3kSrRequested?1:0,g_m3kStartupPrimeActive?1:0);
'@
$vk=Once $vk $logOld $logNew 'P2 periodic diagnostics'

foreach($marker in @(
    'M3K-FSR-P2: independent FSR render planner',
    'DLSS startup prime BYPASSED for FSR backend',
    'Never create/swap a DLSS SR feature',
    'ffxFsr3UpscalerGetJitterPhaseCount',
    'M3K-FSR-P2: isolated planner source='
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR P2 verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'FSR-P2 independent render-planner stage applied.'
