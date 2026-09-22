[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference = 'Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count=0; $pos=0
    while (($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal)) -ge 0) { $count++; $pos=$i+$Old.Length }
    if ($count -ne 1) { throw "Next controls ${Label}: expected one match, found $count" }
    return $Text.Replace($Old,$New)
}
function All([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count=0; $pos=0
    while (($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal)) -ge 0) { $count++; $pos=$i+$Old.Length }
    if ($count -lt 1) { throw "Next controls ${Label}: no matches" }
    Write-Host "  ${Label}: $count match(es)"
    return $Text.Replace($Old,$New)
}

$nrPath=Join-Path $GeneratedRoot 'm3k_nr.h'
$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
foreach($p in @($nrPath,$vkPath,$FeederSource)){if(-not(Test-Path -LiteralPath $p)){throw "Missing generated source: $p"}}
$nr=[IO.File]::ReadAllText($nrPath)
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

# ---- Feature 18 tuning state. Changing tuning rebuilds the independent NR chain once. ----
$nrState = @'
    unsigned passes_ = 1;
    unsigned nrStyle_ = 0, nrAutoMask_ = 1, nrUiCorrection_ = 0;
    float nrIntensity_ = 1.0f, nrLocalTone_ = 1.0f, nrLocalStructure_ = 1.0f, nrSkinStructure_ = 1.0f;
'@
$nr = Once $nr '    unsigned passes_ = 1;' $nrState 'NR state'

$nrPrepareSignature = @'
                 unsigned w, unsigned h, int flags, unsigned requestedPasses = 1,
                 unsigned nrStyle = 0, float nrIntensity = 1.0f, float nrLocalTone = 1.0f,
                 float nrLocalStructure = 1.0f, float nrSkinStructure = 1.0f,
                 unsigned nrAutoMask = 1, unsigned nrUiCorrection = 0) {
'@
$nr = Once $nr '                 unsigned w, unsigned h, int flags, unsigned requestedPasses = 1) {' $nrPrepareSignature 'NR Prepare signature'

$nrClamp = @'
        if (requestedPasses > MaxPasses) requestedPasses = MaxPasses;
        if (nrStyle > 2) nrStyle = 0;
        const auto clampNr=[](float v){return v<0.0f?0.0f:(v>2.0f?2.0f:v);};
        nrIntensity=clampNr(nrIntensity); nrLocalTone=clampNr(nrLocalTone);
        nrLocalStructure=clampNr(nrLocalStructure); nrSkinStructure=clampNr(nrSkinStructure);
        nrAutoMask=nrAutoMask?1u:0u; nrUiCorrection=nrUiCorrection?1u:0u;
'@
$nr = Once $nr '        if (requestedPasses > MaxPasses) requestedPasses = MaxPasses;' $nrClamp 'NR clamp'

$nrRebuildGate = @'
            (device_ != device || w_ != w || h_ != h || flags_ != flags || passes_ != requestedPasses ||
             nrStyle_ != nrStyle || nrIntensity_ != nrIntensity || nrLocalTone_ != nrLocalTone ||
             nrLocalStructure_ != nrLocalStructure || nrSkinStructure_ != nrSkinStructure ||
             nrAutoMask_ != nrAutoMask || nrUiCorrection_ != nrUiCorrection)) {
'@
$nr = Once $nr '            (device_ != device || w_ != w || h_ != h || flags_ != flags || passes_ != requestedPasses)) {' $nrRebuildGate 'NR rebuild gate'

$nrReadyGate = @'
            return Ready() && device_ == device && w_ == w && h_ == h && flags_ == flags && passes_ == requestedPasses &&
                nrStyle_ == nrStyle && nrIntensity_ == nrIntensity && nrLocalTone_ == nrLocalTone &&
                nrLocalStructure_ == nrLocalStructure && nrSkinStructure_ == nrSkinStructure &&
                nrAutoMask_ == nrAutoMask && nrUiCorrection_ == nrUiCorrection;
'@
$nr = Once $nr '            return Ready() && device_ == device && w_ == w && h_ == h && flags_ == flags && passes_ == requestedPasses;' $nrReadyGate 'NR ready gate'

$nrAssign = @'
        w_ = w; h_ = h; flags_ = flags; passes_ = requestedPasses;
        nrStyle_=nrStyle; nrIntensity_=nrIntensity; nrLocalTone_=nrLocalTone;
        nrLocalStructure_=nrLocalStructure; nrSkinStructure_=nrSkinStructure;
        nrAutoMask_=nrAutoMask; nrUiCorrection_=nrUiCorrection;
'@
$nr = Once $nr '        w_ = w; h_ = h; flags_ = flags; passes_ = requestedPasses;' $nrAssign 'NR assign'

$nrParameterOverride = @'
            m3k::CreateContract(pass_[i].params, w, h, flags);
            pass_[i].params->Set("DLSSNR.Style", nrStyle_);
            pass_[i].params->Set("DLSSNR.Intensity", nrIntensity_);
            pass_[i].params->Set("DLSSNR.LocalToneStrength", nrLocalTone_);
            pass_[i].params->Set("DLSSNR.LocalStructureStrength", nrLocalStructure_);
            pass_[i].params->Set("DLSSNR.SkinStructureStrength", nrSkinStructure_);
            pass_[i].params->Set("DLSSNR.UseAutoMask", nrAutoMask_);
            pass_[i].params->Set("DLSSNR.UICorrection", nrUiCorrection_);
'@
$nr = Once $nr '            m3k::CreateContract(pass_[i].params, w, h, flags);' $nrParameterOverride 'NR parameter override'

$publicState = @'
static UINT g_m3kNrPasses = 1;
static UINT g_m3kNrStyle=0, g_m3kNrAutoMask=1, g_m3kNrUiCorrection=0;
static float g_m3kNrIntensity=1.0f, g_m3kNrLocalTone=1.0f, g_m3kNrLocalStructure=1.0f, g_m3kNrSkinStructure=1.0f;
static UINT g_m3kCustomScalePercent=77;
static bool g_m3kCustomScaleRejected=false;
static float g_m3kSharpness=0.0f;
static UINT g_m3kJitterMode=0; // 0=Auto, otherwise explicit phase count (8/16/32)
static UINT g_m3kJitterEffectivePhases=0;
static UINT g_m3kJitterCompMode=0; // 0=current -1/-1; diagnostic NGX-only compensation selector
'@
$vk = Once $vk 'static UINT g_m3kNrPasses = 1;' $publicState 'public state'

$prepareAt=$vk.IndexOf('static void M3kPrepareFrame()',[StringComparison]::Ordinal)
if($prepareAt -lt 0){throw 'M3kPrepareFrame marker missing'}
$floatReader=@'
static float M3kReadPublicFloat(const wchar_t *path,const wchar_t *key,float fallback)
{
    wchar_t def[32]={}, text[32]={};
    _snwprintf_s(def,_TRUNCATE,L"%.3f",static_cast<double>(fallback));
    GetPrivateProfileStringW(L"M3K",key,def,text,static_cast<DWORD>(_countof(text)),path);
    wchar_t *end=nullptr; const float v=wcstof(text,&end); return end==text?fallback:v;
}
static float M3kClampPublicNr(float v){return v<0.0f?0.0f:(v>2.0f?2.0f:v);}
static float M3kJitterCompX()
{
    switch(g_m3kJitterCompMode){
        case 1:return 1.0f; case 2:return 1.0f; case 3:return -1.0f;
        case 4:return -0.5f; case 5:return -2.0f; case 6:return 0.0f;
        default:return -1.0f;
    }
}
static float M3kJitterCompY()
{
    switch(g_m3kJitterCompMode){
        case 1:return 1.0f; case 2:return -1.0f; case 3:return 1.0f;
        case 4:return -0.5f; case 5:return -2.0f; case 6:return 0.0f;
        default:return -1.0f;
    }
}

'@
$vk=$vk.Substring(0,$prepareAt)+$floatReader+$vk.Substring($prepareAt)
$poll='        const UINT nrPasses = requestedPasses < 1 ? 1 : (requestedPasses > 5 ? 5 : requestedPasses);'
$pollNew=@'
        const UINT nrPasses = requestedPasses < 1 ? 1 : (requestedPasses > 5 ? 5 : requestedPasses);
        const UINT rawStyle=GetPrivateProfileIntW(L"M3K",L"NRStyle",0,path);
        const UINT nrStyle=rawStyle<=2?rawStyle:0;
        const float nrIntensity=M3kClampPublicNr(M3kReadPublicFloat(path,L"NRIntensity",1.0f));
        const float nrTone=M3kClampPublicNr(M3kReadPublicFloat(path,L"NRLocalTone",1.0f));
        const float nrStructure=M3kClampPublicNr(M3kReadPublicFloat(path,L"NRLocalStructure",1.0f));
        const float nrSkin=M3kClampPublicNr(M3kReadPublicFloat(path,L"NRSkinStructure",1.0f));
        const UINT nrMask=GetPrivateProfileIntW(L"M3K",L"NRAutoMask",1,path)?1u:0u;
        const UINT nrUi=GetPrivateProfileIntW(L"M3K",L"NRUICorrection",0,path)?1u:0u;
        if(nrStyle!=g_m3kNrStyle || nrIntensity!=g_m3kNrIntensity || nrTone!=g_m3kNrLocalTone ||
           nrStructure!=g_m3kNrLocalStructure || nrSkin!=g_m3kNrSkinStructure || nrMask!=g_m3kNrAutoMask || nrUi!=g_m3kNrUiCorrection){
            g_m3kNrStyle=nrStyle; g_m3kNrIntensity=nrIntensity; g_m3kNrLocalTone=nrTone;
            g_m3kNrLocalStructure=nrStructure; g_m3kNrSkinStructure=nrSkin;
            g_m3kNrAutoMask=nrMask; g_m3kNrUiCorrection=nrUi; g_m3k.ResetHistory();
#if defined(VK_VERSION_1_0)
            g_m3kSrNeedsReset=true;
#endif
        }
        const float sharpness=M3kReadPublicFloat(path,L"Sharpness",0.0f);
        g_m3kSharpness=sharpness<0.0f?0.0f:(sharpness>1.5f?1.5f:sharpness);
        const UINT rawJitterMode=GetPrivateProfileIntW(L"M3K",L"JitterMode",0,path);
        g_m3kJitterMode=(rawJitterMode==8||rawJitterMode==16||rawJitterMode==32)?rawJitterMode:0u;
        const UINT rawJitterComp=GetPrivateProfileIntW(L"M3K",L"JitterCompMode",0,path);
        g_m3kJitterCompMode=rawJitterComp<=6?rawJitterComp:0u;
        const UINT rawScale=GetPrivateProfileIntW(L"M3K",L"CustomScalePercent",77,path);
        const UINT customScale=rawScale<10?10:(rawScale>100?100:rawScale);
        if(customScale!=g_m3kCustomScalePercent){
            g_m3kCustomScalePercent=customScale;
            if(g_m3kSrProfileRequested==6){g_m3kResolutionPlanProfile=0xFFFFFFFFu;g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;g_m3kResolutionConfirmedLogged=false;g_m3kSrNeedsReset=true;g_m3k.ResetHistory();}
        }
'@
$vk=Once $vk $poll $pollNew 'INI poll'
$vk=Once $vk '        sr.InJitterOffsetX = bridgeJitterActive ? -bridgeJitter.jitterX : 0.0f;' '        sr.InJitterOffsetX = bridgeJitterActive ? bridgeJitter.jitterX*M3kJitterCompX() : 0.0f;' 'SR jitter compensation X'
$vk=Once $vk '        sr.InJitterOffsetY = bridgeJitterActive ? -bridgeJitter.jitterY : 0.0f;' '        sr.InJitterOffsetY = bridgeJitterActive ? bridgeJitter.jitterY*M3kJitterCompY() : 0.0f;' 'SR jitter compensation Y'
$vk=Once $vk 'g_m3k.Prepare(g_self, g.dev12, g.queue, g_m3kSrW, g_m3kSrH, g.create_flags, g_m3kNrPasses);' 'g_m3k.Prepare(g_self,g.dev12,g.queue,g_m3kSrW,g_m3kSrH,g.create_flags,g_m3kNrPasses,g_m3kNrStyle,g_m3kNrIntensity,g_m3kNrLocalTone,g_m3kNrLocalStructure,g_m3kNrSkinStructure,g_m3kNrAutoMask,g_m3kNrUiCorrection);' 'SR NR handoff'
$vk=Once $vk 'g_m3k.Prepare(g_self, g.dev12, g.queue, g.width, g.height, g.create_flags, g_m3kNrPasses);' 'g_m3k.Prepare(g_self,g.dev12,g.queue,g.width,g.height,g.create_flags,g_m3kNrPasses,g_m3kNrStyle,g_m3kNrIntensity,g_m3kNrLocalTone,g_m3kNrLocalStructure,g_m3kNrSkinStructure,g_m3kNrAutoMask,g_m3kNrUiCorrection);' 'native NR handoff'
$nativeDlaaOld=@'
    // Existing A1 path: copy the whole baseline contract. Only Color/reset at the
    // A/B boundary may differ; temporal guides/exposure/scale/mask stay identical.
    auto dlaa = *ep;
'@
$nativeDlaaNew=@'
    // Native DLAA must receive the SAME temporal sample that was applied to GTA's
    // raster by the 32-bit bridge. A3-S1 originally synchronized only the SR branch;
    // leaving native DLAA at jitter=(0,0) while GTA was jittered made DLAA look like
    // native/no-AA and broke temporal accumulation.
    auto dlaa = *ep;
    M3kBridgeJitterSnapshot dlaaBridgeJitter;
    const bool dlaaBridgeJitterReadable = M3kReadBridgeJitter(&dlaaBridgeJitter);
    const bool dlaaBridgeJitterActive = dlaaBridgeJitterReadable && dlaaBridgeJitter.valid &&
        dlaaBridgeJitter.active && dlaaBridgeJitter.renderWidth == g.width &&
        dlaaBridgeJitter.renderHeight == g.height;
    const bool dlaaBridgeJitterTransition = !g_m3kJitterStateKnown
        ? dlaaBridgeJitterActive
        : (dlaaBridgeJitterActive != g_m3kJitterLastActive) ||
          (dlaaBridgeJitterActive && dlaaBridgeJitter.epoch != g_m3kJitterLastEpoch);
    // NGX-only diagnostic compensation; raster jitter itself is unchanged.
    dlaa.InJitterOffsetX = dlaaBridgeJitterActive ? dlaaBridgeJitter.jitterX*M3kJitterCompX() : 0.0f;
    dlaa.InJitterOffsetY = dlaaBridgeJitterActive ? dlaaBridgeJitter.jitterY*M3kJitterCompY() : 0.0f;
    if(dlaaBridgeJitterTransition) dlaa.InReset = 1;
'@
$vk=Once $vk $nativeDlaaOld $nativeDlaaNew 'native DLAA synchronized jitter'

$nativeDlaaResultOld=@'
    const NVSDK_NGX_Result result = SafeEvaluateDLSS(&dlaa, code);
    if (used && *code == 0) g_m3k.Finish(g.list);
'@
$nativeDlaaResultNew=@'
    const NVSDK_NGX_Result result = SafeEvaluateDLSS(&dlaa, code);
    if(*code==0 && NVSDK_NGX_SUCCEED(result)){
        g_m3kJitterStateKnown=true;
        g_m3kJitterLastActive=dlaaBridgeJitterActive;
        g_m3kJitterLastEpoch=dlaaBridgeJitterActive?dlaaBridgeJitter.epoch:-1;
        g_m3kJitterLastFrame=dlaaBridgeJitterActive?dlaaBridgeJitter.frame:-1;
        static UINT64 dlaaJitterFrames=0;
        ++dlaaJitterFrames;
        if(dlaaJitterFrames==1 || (dlaaJitterFrames%300)==0 || dlaaBridgeJitterTransition)
            Log("M3K-DLAA-JITTER: active=%d bridgeFrame=%ld epoch=%ld native=%ux%u ngxPx=(%+.4f,%+.4f) reset=%d",
                dlaaBridgeJitterActive?1:0,
                dlaaBridgeJitterActive?dlaaBridgeJitter.frame:-1,
                dlaaBridgeJitterActive?dlaaBridgeJitter.epoch:-1,
                g.width,g.height,dlaa.InJitterOffsetX,dlaa.InJitterOffsetY,dlaa.InReset);
    }
    if (used && *code == 0) g_m3k.Finish(g.list);
'@
$vk=Once $vk $nativeDlaaResultOld $nativeDlaaResultNew 'native DLAA jitter state commit'


# ---- Profile 6 = custom percentage. Existing named profiles 0..5 are unchanged. ----
$profileNameNew = '        case 5: return "Ultra Performance";' + [Environment]::NewLine + '        case 6: return "Custom Render Scale";'
$vk = Once $vk '        case 5: return "Ultra Performance";' $profileNameNew 'profile name'
$vk=All $vk 'if (profile > 5) profile = 2;' 'if (profile > 6) profile = 2;' 'profile bounds'
$vk=All $vk 'g_m3kMasterSavedProfile <= 5 ? g_m3kMasterSavedProfile : 2' 'g_m3kMasterSavedProfile <= 6 ? g_m3kMasterSavedProfile : 2' 'master restore bounds'
$vk=All $vk 'savedProfileRaw <= 5 ? savedProfileRaw : 2' 'savedProfileRaw <= 6 ? savedProfileRaw : 2' 'master INI bounds'
$vk=All $vk 'requestedSrProfile <= 5 ? requestedSrProfile : 2' 'requestedSrProfile <= 6 ? requestedSrProfile : 2' 'SR INI bounds'
$vk=All $vk 'g_m3kStartupPrimeInitialProfile <= 5' 'g_m3kStartupPrimeInitialProfile <= 6' 'prime initial bounds'
$vk=All $vk 'g_m3kSrProfileRequested > 5' 'g_m3kSrProfileRequested > 6' 'prime requested bounds'

$findAt=$vk.IndexOf('static bool M3kReadManualRenderSize(UINT *manualW, UINT *manualH)',[StringComparison]::Ordinal)
if($findAt -lt 0){throw 'custom contract insertion marker missing'}
$finder=@'
struct M3kCustomContract{NVSDK_NGX_PerfQuality_Value q;const char *name;const char *hint;};
static bool M3kFindCustomContract(UINT rw,UINT rh,UINT tw,UINT th,M3kCustomContract *out)
{
    if(!rw||!rh||!tw||!th)return false;
    const float sx=static_cast<float>(rw)/static_cast<float>(tw);
    const float sy=static_cast<float>(rh)/static_cast<float>(th);
    const float scale=sx<sy?sx:sy;
    M3kCustomContract pick={NVSDK_NGX_PerfQuality_Value_UltraPerformance,"Ultra Performance",NVSDK_NGX_Parameter_DLSS_Hint_Render_Preset_UltraPerformance};
    if(scale>=0.625f) pick={NVSDK_NGX_PerfQuality_Value_MaxQuality,"Quality",NVSDK_NGX_Parameter_DLSS_Hint_Render_Preset_Quality};
    else if(scale>=0.540f) pick={NVSDK_NGX_PerfQuality_Value_Balanced,"Balanced",NVSDK_NGX_Parameter_DLSS_Hint_Render_Preset_Balanced};
    else if(scale>=0.415f) pick={NVSDK_NGX_PerfQuality_Value_MaxPerf,"Performance",NVSDK_NGX_Parameter_DLSS_Hint_Render_Preset_Performance};
    if(out)*out=pick;
    Log("M3K-CUSTOM-SCALE: FORCED %ux%u -> %ux%u (%.1f%%), attempting %s contract without NGX range pre-rejection",rw,rh,tw,th,scale*100.0f,pick.name);
    return true;
}

'@
$vk=$vk.Substring(0,$findAt)+$finder+$vk.Substring($findAt)
$queryFn = 'static bool M3kQueryProfileRenderSize(UINT profile, UINT targetW, UINT targetH, UINT *renderW, UINT *renderH)'
$queryAt = $vk.IndexOf($queryFn,[StringComparison]::Ordinal)
if($queryAt -lt 0){throw 'custom size query function missing'}
$queryBodyAt = $vk.IndexOf('    if (!renderW || !renderH || !targetW || !targetH) return false;',$queryAt,[StringComparison]::Ordinal)
if($queryBodyAt -lt 0){throw 'custom size query validity line missing'}
$queryBodyEnd = $queryBodyAt + '    if (!renderW || !renderH || !targetW || !targetH) return false;'.Length
$customQueryInsert = @'

    if(profile==6){
        const UINT p=g_m3kCustomScalePercent<10?10:(g_m3kCustomScalePercent>100?100:g_m3kCustomScalePercent);
        if(p>=100){*renderW=targetW;*renderH=targetH;return true;}
        const UINT rw=(targetW*p+50u)/100u,rh=(targetH*p+50u)/100u;
        *renderW=rw;*renderH=rh;Log("M3K-CUSTOM-SCALE: forcing %u%% true source %ux%u -> %ux%u",p,rw,rh,targetW,targetH);return true;
    }
'@
$vk = $vk.Substring(0,$queryBodyEnd) + $customQueryInsert + $vk.Substring($queryBodyEnd)
$select='    if (profile < 1 || profile > 5) return false;'
$selectNew=@'
    if (profile < 1 || profile > 6) return false;
    if(profile==6){M3kCustomContract c={};if(!M3kFindCustomContract(renderW,renderH,targetW,targetH,&c))return false;
        g.sr_quality=static_cast<int>(c.q);g.sr_quality_name="Custom Render Scale";g.sr_quality_hint=c.hint;
        Log("M3K-CUSTOM-SCALE: using %s contract %ux%u -> %ux%u",c.name,renderW,renderH,targetW,targetH);return true;}
'@
$vk=Once $vk $select $selectNew 'custom feature contract'
$vk=Once $vk 'const UINT fallback = g_m3kSrProfileApplied <= 5 ? g_m3kSrProfileApplied : 2;' 'const UINT fallback = (g_m3kSrProfileApplied <= 6 && g_m3kSrProfileApplied != 6) ? g_m3kSrProfileApplied : 2;' 'custom fallback'

$customFailOld=@'
        Log("M3K-SR-LIVE: %s feature create %s; keeping currently applied reconstruction",
            M3kSrProfileName(g_m3kSrProfileRequested), crashed ? "crashed (caught)" : "failed");
        return false;
'@
$customFailNew=@'
        if(g_m3kSrProfileRequested==6)g_m3kCustomScaleRejected=true;
        Log("M3K-SR-LIVE: %s feature create %s; keeping currently applied reconstruction",
            M3kSrProfileName(g_m3kSrProfileRequested), crashed ? "crashed (caught)" : "failed");
        return false;
'@
$vk=Once $vk $customFailOld $customFailNew 'custom actual-create failure status'

$customSameDimsOld=@'
        if (!M3kSwapToSrFeature(info.width, info.height, info.presenterWidth, info.presenterHeight))
        {
            Log("M3K-SR-LIVE: requested %s rejected; keeping %s",
                M3kSrProfileName(wanted), M3kSrProfileName(g_m3kSrProfileApplied));
            g_m3kSrProfileRequested = g_m3kSrProfileApplied;
            M3kWriteSrProfileIni(g_m3kSrProfileRequested);
        }
'@
$customSameDimsNew=@'
        if (!M3kSwapToSrFeature(info.width, info.height, info.presenterWidth, info.presenterHeight))
        {
            Log("M3K-SR-LIVE: requested %s rejected by feature creation; keeping %s",
                M3kSrProfileName(wanted), M3kSrProfileName(g_m3kSrProfileApplied));
            if(wanted==6){g_m3kCustomScaleRejected=true;g_m3kSrLatchedFail=true;}
            else {g_m3kSrProfileRequested = g_m3kSrProfileApplied;M3kWriteSrProfileIni(g_m3kSrProfileRequested);}
        }
'@
$vk=Once $vk $customSameDimsOld $customSameDimsNew 'custom selector stability'

# Public setters/getters are inserted at the final accessor left by the master stages.
$api='static UINT M3kRequestedNrPasses() { return g_m3kNrPasses; }'
$apiNew=@'
static void M3kWritePublicUInt(const wchar_t *key,UINT value){wchar_t path[MAX_PATH]={};if(!GetModuleFileNameW(g_self,path,MAX_PATH))return;if(wchar_t *s=wcsrchr(path,L'\\')){*(s+1)=0;wcscat_s(path,L"m3k-nr.ini");wchar_t t[32]={};_snwprintf_s(t,_TRUNCATE,L"%u",value);WritePrivateProfileStringW(L"M3K",key,t,path);}}
static void M3kWritePublicFloat(const wchar_t *key,float value){wchar_t path[MAX_PATH]={};if(!GetModuleFileNameW(g_self,path,MAX_PATH))return;if(wchar_t *s=wcsrchr(path,L'\\')){*(s+1)=0;wcscat_s(path,L"m3k-nr.ini");wchar_t t[32]={};_snwprintf_s(t,_TRUNCATE,L"%.3f",static_cast<double>(value));WritePrivateProfileStringW(L"M3K",key,t,path);}}
static UINT M3kCustomScalePercent(){return g_m3kCustomScalePercent;} static bool M3kCustomScaleLastRejected(){return g_m3kCustomScaleRejected;}
static UINT M3kScaleW(UINT p){return g.width?(g.width*p+50u)/100u:0;} static UINT M3kScaleH(UINT p){return g.height?(g.height*p+50u)/100u:0;}
static void M3kApplyCustomScaleLive(UINT p){p=p<10?10:(p>100?100:p);g_m3kCustomScaleRejected=false;g_m3kCustomScalePercent=p;M3kWritePublicUInt(L"CustomScalePercent",p);g_m3kResolutionPlanProfile=0xFFFFFFFFu;g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;g_m3kResolutionConfirmedLogged=false;g_m3kSrLatchedFail=false;g_m3kSrNeedsReset=true;g_m3k.ResetHistory();M3kRequestSrProfileLive(p>=100?0:6);g_m3kJitterEffectivePhases=0;}
static float M3kSharpnessRequested(){return g_m3kSharpness;}
static void M3kRequestSharpnessLive(float value){value=value<0.0f?0.0f:(value>1.5f?1.5f:value);g_m3kSharpness=value;M3kWritePublicFloat(L"Sharpness",value);}
static UINT M3kJitterModeRequested(){return g_m3kJitterMode;}
static UINT M3kComputeAutoJitterPhases(){
    UINT rw=0,rh=0;const UINT profile=M3kRequestedSrProfile();
    if(!M3kQueryProfileRenderSize(profile,g.width,g.height,&rw,&rh)||!rw||!rh){rw=g.width;rh=g.height;}
    if(!rw||!rh||!g.width||!g.height)return 8u;
    const float sx=static_cast<float>(g.width)/static_cast<float>(rw);
    const float sy=static_cast<float>(g.height)/static_cast<float>(rh);
    const float ratio=sx>sy?sx:sy;
    const float wanted=8.0f*ratio*ratio;
    UINT phases=static_cast<UINT>(wanted);
    if(static_cast<float>(phases)<wanted)++phases;
    if(phases<8u)phases=8u;if(phases>1024u)phases=1024u;
    return phases;
}
static UINT M3kJitterEffectivePhases(){return g_m3kJitterMode?g_m3kJitterMode:M3kComputeAutoJitterPhases();}
static void M3kSyncJitterPhasesLive(){
    const UINT effective=M3kJitterEffectivePhases();
    if(effective==g_m3kJitterEffectivePhases)return;
    g_m3kJitterEffectivePhases=effective;M3kWritePublicUInt(L"JitterPhases",effective);
    Log("M3K-JITTER-UI: mode=%s effective phases=%u render=%ux%u output=%ux%u",
        g_m3kJitterMode?"Manual":"Auto",effective,M3kDesiredRenderWidth(),M3kDesiredRenderHeight(),g.width,g.height);
}
static void M3kRequestJitterModeLive(UINT mode){
    if(mode!=8u&&mode!=16u&&mode!=32u)mode=0u;
    if(mode==g_m3kJitterMode){M3kSyncJitterPhasesLive();return;}
    g_m3kJitterMode=mode;M3kWritePublicUInt(L"JitterMode",mode);g_m3kJitterEffectivePhases=0;
    M3kSyncJitterPhasesLive();g_m3k.ResetHistory();g_m3kSrNeedsReset=true;
}
static UINT M3kJitterCompModeRequested(){return g_m3kJitterCompMode;}
static void M3kRequestJitterCompModeLive(UINT mode){
    if(mode>6u)mode=0u;
    if(mode==g_m3kJitterCompMode)return;
    g_m3kJitterCompMode=mode;M3kWritePublicUInt(L"JitterCompMode",mode);
    g_m3k.ResetHistory();g_m3kSrNeedsReset=true;
    Log("M3K-JITTER-CAL: NGX compensation mode=%u multiplier=(%+.2f,%+.2f)",mode,M3kJitterCompX(),M3kJitterCompY());
}
static UINT M3kNrStyleRequested(){return g_m3kNrStyle;} static float M3kNrIntensityRequested(){return g_m3kNrIntensity;} static float M3kNrLocalToneRequested(){return g_m3kNrLocalTone;} static float M3kNrLocalStructureRequested(){return g_m3kNrLocalStructure;} static float M3kNrSkinStructureRequested(){return g_m3kNrSkinStructure;} static bool M3kNrAutoMaskRequested(){return g_m3kNrAutoMask!=0;} static bool M3kNrUiCorrectionRequested(){return g_m3kNrUiCorrection!=0;}
static void M3kRequestNrTuningLive(UINT style,float intensity,float tone,float structure,float skin,bool mask,bool ui){style=style>2?0:style;intensity=intensity<0.0f?0.0f:(intensity>2.0f?2.0f:intensity);tone=tone<0.0f?0.0f:(tone>2.0f?2.0f:tone);structure=structure<0.0f?0.0f:(structure>2.0f?2.0f:structure);skin=skin<0.0f?0.0f:(skin>2.0f?2.0f:skin);g_m3kNrStyle=style;g_m3kNrIntensity=intensity;g_m3kNrLocalTone=tone;g_m3kNrLocalStructure=structure;g_m3kNrSkinStructure=skin;g_m3kNrAutoMask=mask?1u:0u;g_m3kNrUiCorrection=ui?1u:0u;M3kWritePublicUInt(L"NRStyle",style);M3kWritePublicFloat(L"NRIntensity",intensity);M3kWritePublicFloat(L"NRLocalTone",tone);M3kWritePublicFloat(L"NRLocalStructure",structure);M3kWritePublicFloat(L"NRSkinStructure",skin);M3kWritePublicUInt(L"NRAutoMask",g_m3kNrAutoMask);M3kWritePublicUInt(L"NRUICorrection",g_m3kNrUiCorrection);g_m3k.ResetHistory();g_m3kSrNeedsReset=true;}
static UINT M3kRequestedNrPasses() { return g_m3kNrPasses; }
'@
$vk=Once $vk $api $apiNew 'public API'

# ---- Replace the final compact panel. Slider edits are staged; only Apply changes render size. ----
$mark='    if (ImGui::CollapsingHeader("GTA IV DLSS", ImGuiTreeNodeFlags_DefaultOpen))'
$start=$feed.IndexOf($mark,[StringComparison]::Ordinal);if($start -lt 0){throw 'final UI marker missing'}
$open=$feed.IndexOf('{',$start);$depth=0;$end=-1
for($i=$open;$i -lt $feed.Length;$i++){if($feed[$i]-eq '{'){$depth++}elseif($feed[$i]-eq '}'){$depth--;if($depth-eq 0){$end=$i+1;break}}}
if($end -lt 0){throw 'final UI closing brace missing'}
$ui=@'
    if (ImGui::CollapsingHeader("GTA IV DLSS", ImGuiTreeNodeFlags_DefaultOpen))
    {
        bool master=M3kMasterEnabledRequested(); if(ImGui::Checkbox("DLSS / DLAA processing##M3KMaster",&master))M3kRequestMasterEnabledLive(master);
        ImGui::SameLine(); ImGui::TextDisabled("%s",master?"ON":"OFF");
        ImGui::Separator(); ImGui::TextUnformatted("Reconstruction");
        ImGui::BeginDisabled(!master); int reconstruction=static_cast<int>(M3kRequestedSrProfile()); if(reconstruction<0||reconstruction>6)reconstruction=2;
        const char *items="DLAA Native (100%)\0Custom Ultra Quality (77%)\0Quality (67%)\0Balanced (58%)\0Performance (50%)\0Ultra Performance (33%)\0Custom Render Scale\0\0";
        if(ImGui::Combo("Mode##M3KSRProfile",&reconstruction,items)){if(reconstruction==6)M3kApplyCustomScaleLive(M3kCustomScalePercent());else M3kRequestSrProfileLive(static_cast<UINT>(reconstruction));}
        ImGui::EndDisabled();
        const int saved=static_cast<int>(M3kCustomScalePercent()); static int draft=-1,seen=-1;
        if(draft<10||draft>100){draft=saved;seen=saved;}else if(saved!=seen){if(draft==seen)draft=saved;seen=saved;}
        ImGui::BeginDisabled(!master); ImGui::SliderInt("Render Scale##M3KCustomScale",&draft,10,100,"%d%%");
        if(draft!=saved){ImGui::SameLine();if(ImGui::Button("Apply##M3KCustomScaleApply"))M3kApplyCustomScaleLive(static_cast<UINT>(draft));} ImGui::EndDisabled();
        if(draft>=100)ImGui::Text("100%% = DLAA Native (%u x %u)",M3kScaleW(100),M3kScaleH(100));else ImGui::Text("Custom preview: %d%% = %u x %u -> %u x %u",draft,M3kScaleW(static_cast<UINT>(draft)),M3kScaleH(static_cast<UINT>(draft)),g.width,g.height);
        if(M3kCustomScaleLastRejected())ImGui::TextColored(ImVec4(1.0f,0.45f,0.35f,1.0f),"NVIDIA rejected feature creation at this forced scale; previous reconstruction is still displayed.");

        static float sharpDraft=-1.0f; if(sharpDraft<0.0f)sharpDraft=M3kSharpnessRequested();
        ImGui::BeginDisabled(!master); if(ImGui::SliderFloat("Sharpening##M3KSharpness",&sharpDraft,0.0f,1.5f,"%.2f"))M3kRequestSharpnessLive(sharpDraft); ImGui::EndDisabled();
        ImGui::TextDisabled("0.00 = off   0.35 = mild   0.75 = strong   1.50 = extreme");

        M3kSyncJitterPhasesLive();
        int jitterChoice=0;const UINT jitterMode=M3kJitterModeRequested();if(jitterMode==8)jitterChoice=1;else if(jitterMode==16)jitterChoice=2;else if(jitterMode==32)jitterChoice=3;
        const char *jitterItems="Auto\0" "8 phases\0" "16 phases\0" "32 phases\0\0";
        ImGui::BeginDisabled(!master);if(ImGui::Combo("Jitter Sequence##M3KJitterPhases",&jitterChoice,jitterItems)){const UINT modes[4]={0u,8u,16u,32u};M3kRequestJitterModeLive(modes[jitterChoice]);}ImGui::EndDisabled();
        ImGui::TextDisabled("Effective: %u phases%s",M3kJitterEffectivePhases(),M3kJitterModeRequested()==0?" (Auto)":"");

        int jitterComp=static_cast<int>(M3kJitterCompModeRequested());
        const char *jitterCompItems="Current -1/-1\0" "Same sign +1/+1\0" "Flip X +1/-1\0" "Flip Y -1/+1\0" "Half -0.5/-0.5\0" "Double -2/-2\0" "Off 0/0\0\0";
        ImGui::BeginDisabled(!master);if(ImGui::Combo("NGX Jitter Compensation##M3KJitterComp",&jitterComp,jitterCompItems))M3kRequestJitterCompModeLive(static_cast<UINT>(jitterComp));ImGui::EndDisabled();
        ImGui::TextDisabled("Diagnostic: changes NGX offset only; raster jitter stays identical.");

        ImGui::Text("Current: %s",M3kSrProfileName(M3kAppliedSrProfile())); if(master&&M3kAppliedSrProfile()!=M3kRequestedSrProfile())ImGui::TextColored(ImVec4(1.0f,0.78f,0.25f,1.0f),"Applying %s...",M3kSrProfileName(M3kRequestedSrProfile()));

        ImGui::Separator(); ImGui::TextUnformatted("Neural Rendering"); bool nr=M3kNrEnabledRequested(); ImGui::BeginDisabled(!master); if(ImGui::Checkbox("Enable Neural Rendering##M3KNrEnabled",&nr))M3kRequestNrEnabledLive(nr); ImGui::EndDisabled();
        if(ImGui::CollapsingHeader("Advanced##M3KAdvanced")){
            ImGui::BeginDisabled(!master||!nr); int style=static_cast<int>(M3kNrStyleRequested()); const char *styles="Default\0Natural\0Cinematic\0\0";
            if(ImGui::Combo("NR Style##M3KNrStyle",&style,styles))M3kRequestNrTuningLive(static_cast<UINT>(style),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
            static float i=-1,t=-1,s=-1,skin=-1; if(i<0)i=M3kNrIntensityRequested();if(t<0)t=M3kNrLocalToneRequested();if(s<0)s=M3kNrLocalStructureRequested();if(skin<0)skin=M3kNrSkinStructureRequested();
            ImGui::SliderFloat("Intensity##M3KNrIntensity",&i,0.0f,2.0f,"%.2f");if(ImGui::IsItemDeactivatedAfterEdit())M3kRequestNrTuningLive(M3kNrStyleRequested(),i,M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
            ImGui::SliderFloat("Local Tone##M3KNrTone",&t,0.0f,2.0f,"%.2f");if(ImGui::IsItemDeactivatedAfterEdit())M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),t,M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
            ImGui::SliderFloat("Local Structure##M3KNrStructure",&s,0.0f,2.0f,"%.2f");if(ImGui::IsItemDeactivatedAfterEdit())M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),s,M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
            ImGui::SliderFloat("Skin Structure##M3KNrSkin",&skin,0.0f,2.0f,"%.2f");if(ImGui::IsItemDeactivatedAfterEdit())M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),skin,M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
            bool mask=M3kNrAutoMaskRequested();if(ImGui::Checkbox("Auto Mask##M3KNrAutoMask",&mask))M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),mask,M3kNrUiCorrectionRequested());
            bool ui=M3kNrUiCorrectionRequested();if(ImGui::Checkbox("UI Correction##M3KNrUiCorrection",&ui))M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),ui);
            if(ImGui::Button("Reset NR Advanced##M3KNrReset")){i=1.0f;t=1.0f;s=1.0f;skin=1.0f;M3kRequestNrTuningLive(0,1.0f,1.0f,1.0f,1.0f,true,false);}
            ImGui::SameLine();ImGui::TextDisabled("Default style, 1.00 strengths, Auto Mask on, UI Correction off");
            ImGui::Spacing(); const UINT requested=M3kRequestedNrPasses(); ImGui::TextUnformatted("Neural Rendering passes");
            for(UINT p=1;p<=5;++p){if(p>1)ImGui::SameLine();char label[24]={};_snprintf_s(label,sizeof(label),_TRUNCATE,"%u##M3KPass",p);if(ImGui::RadioButton(label,requested==p))M3kRequestNrPassesLive(p);} ImGui::Text("Active passes: %u",M3kActiveNrPasses()); ImGui::EndDisabled();}
        if(ImGui::CollapsingHeader("Diagnostics##M3KDiagnostics")){ImGui::Text("Requested render: %u x %u",M3kDesiredRenderWidth(),M3kDesiredRenderHeight());ImGui::Text("DXVK source: %u x %u",M3kCurrentSourceWidth(),M3kCurrentSourceHeight());ImGui::Text("Output: %u x %u",g.width,g.height);ImGui::Text("Saved custom scale: %u%%",M3kCustomScalePercent());ImGui::Text("Jitter: mode=%s effective=%u phases comp=%u (%+.2f,%+.2f)",M3kJitterModeRequested()==0?"Auto":"Manual",M3kJitterEffectivePhases(),M3kJitterCompModeRequested(),M3kJitterCompX(),M3kJitterCompY());ImGui::Text("NR style=%u intensity=%.2f tone=%.2f structure=%.2f skin=%.2f",M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested());}
        ImGui::Separator();
    }
'@
$feed=$feed.Substring(0,$start)+$ui+$feed.Substring($end)

$sharpenFnMarker='static void OnRenderTechnique(reshade::api::effect_runtime *rt, reshade::api::effect_technique technique,'
$sharpenFnAt=$feed.IndexOf($sharpenFnMarker,[StringComparison]::Ordinal)
if($sharpenFnAt -lt 0){throw 'sharpen OnRenderTechnique marker missing'}
$sharpenHelpers=@'
static reshade::api::effect_runtime *g_m3kSharpenRuntime=nullptr;
static reshade::api::effect_uniform_variable g_m3kSharpenUniform={};
static ULONGLONG g_m3kSharpenNextResolve=0;

static void M3kSyncSharpenUniform(reshade::api::effect_runtime *rt)
{
    M3kSyncJitterPhasesLive();
    const ULONGLONG now=GetTickCount64();
    if(rt!=g_m3kSharpenRuntime || now>=g_m3kSharpenNextResolve)
    {
        g_m3kSharpenRuntime=rt;
        g_m3kSharpenNextResolve=now+1000;
        g_m3kSharpenUniform=rt->find_uniform_variable("M3K_Sharpen.fx","M3K_Sharpness");
        if(g_m3kSharpenUniform.handle==0)
            Log("M3K-SHARPEN: M3K_Sharpness uniform not found; normal DLSS/NR processing is unaffected");
    }
    if(g_m3kSharpenUniform.handle!=0)
        rt->set_uniform_value_float(g_m3kSharpenUniform,M3kSharpnessRequested());
}

'@
$feed=$feed.Substring(0,$sharpenFnAt)+$sharpenHelpers+$feed.Substring($sharpenFnAt)
$renderOld=@'
    g_bound_last_render = GetTickCount64();
    FeedFrame(rt, cl, rtv);
'@
$renderNew=@'
    g_bound_last_render = GetTickCount64();
    if(M3kRuntimeChurnHeld())
    {
        static ULONGLONG lastHoldLog=0;
        const ULONGLONG now=GetTickCount64();
        if(now-lastHoldLog>=500){lastHoldLog=now;Log("M3K-SAFE-RESIZE: DLSS submission skipped while ReShade runtime churn settles");}
        return;
    }
    FeedFrame(rt, cl, rtv);
'@
$feed=Once $feed $renderOld $renderNew 'quarantine FeedFrame during runtime churn'
$feed=Once $feed '    FeedFrame(rt, cl, rtv);' ('    FeedFrame(rt, cl, rtv);' + [Environment]::NewLine + '    M3kSyncSharpenUniform(rt);') 'post-DLSS sharpen uniform sync'

# ---- Vulkan resize/runtime-churn safety: never ReleaseFeature from inside ReShade runtime destruction. ----
# The user crash log showed a foreign-thread 0xC0000005 in ReShade64.dll while
# ReleaseFrameResources -> SafeReleaseFeature ran during the 1485x835 -> native swapchain rebuild.
# ReShade/NGX hooks are re-arming at this exact point. Detach the handle, rebuild game-side
# imports/resources normally, then release the old NGX feature only after the existing
# create-grace has elapsed on the fresh runtime.
$vkFrameDecl='static void FeedFrameVk('
$vkFrameAt=$feed.IndexOf($vkFrameDecl,[StringComparison]::Ordinal)
if($vkFrameAt -lt 0){throw 'Vulkan frame declaration anchor missing'}
$feed=$feed.Substring(0,$vkFrameAt)+"static void M3kReleaseDeferredRuntimeChurnFeature();`r`n`r`n"+$feed.Substring($vkFrameAt)

$deferAnchor='static void OnDestroyEffectRuntime(reshade::api::effect_runtime *rt)'
$deferAt=$feed.IndexOf($deferAnchor,[StringComparison]::Ordinal)
if($deferAt -lt 0){throw 'runtime-destroy safety anchor missing'}
$deferHelpers=@'
static NVSDK_NGX_Handle *g_m3kDeferredRuntimeChurnFeature=nullptr;
static volatile LONG64 g_m3kRuntimeChurnHoldUntil=0;

static void M3kArmRuntimeChurnHold()
{
    const LONG64 until=static_cast<LONG64>(GetTickCount64()+1800ull);
    InterlockedExchange64(&g_m3kRuntimeChurnHoldUntil,until);
    Log("M3K-SAFE-RESIZE: runtime churn quarantine armed for 1800 ms; DLSS submissions paused");
}

static bool M3kRuntimeChurnHeld()
{
    const LONG64 until=InterlockedCompareExchange64(&g_m3kRuntimeChurnHoldUntil,0,0);
    return until>0 && static_cast<LONG64>(GetTickCount64())<until;
}

static void M3kDeferRuntimeChurnFeatureRelease()
{
    if(g.feature==nullptr)return;
    if(g_m3kDeferredRuntimeChurnFeature!=nullptr && g_m3kDeferredRuntimeChurnFeature!=g.feature)
    {
        // This should not normally happen: no new feature is built until the fresh runtime
        // survives its hook grace. If it does, keep the older handle alive rather than make
        // an unsafe NGX call from the runtime-destroy callback.
        Log("M3K-SAFE-RESIZE: another runtime teardown arrived before deferred feature release; preserving older handle until process exit");
    }
    else
    {
        g_m3kDeferredRuntimeChurnFeature=g.feature;
    }
    g.feature=nullptr;
    Log("M3K-SAFE-RESIZE: detached old DLSS feature from ReShade runtime teardown; release deferred until fresh-runtime grace");
}

static void M3kReleaseDeferredRuntimeChurnFeature()
{
    if(g_m3kDeferredRuntimeChurnFeature==nullptr)return;
    NVSDK_NGX_Handle *old=g_m3kDeferredRuntimeChurnFeature;
    g_m3kDeferredRuntimeChurnFeature=nullptr;
    Breadcrumb("releasing deferred DLSS feature after runtime grace");
    Log("M3K-SAFE-RESIZE: fresh runtime survived hook grace; releasing deferred DLSS feature now");
    SafeReleaseFeature(old);
}

'@
$feed=$feed.Substring(0,$deferAt)+$deferHelpers+$feed.Substring($deferAt)

$destroyOld='    if (g.dev12_owned && g.dev11 == nullptr) ReleaseFrameResources();'
$destroyNew=@'
    if (g.dev12_owned && g.dev11 == nullptr)
    {
        M3kDeferRuntimeChurnFeatureRelease();
        ReleaseFrameResources();
    }
'@
$feed=Once $feed $destroyOld $destroyNew 'defer feature release during Vulkan runtime destruction'
$feed=Once $feed '    if (!was_bound) return;' ('    if (!was_bound) return;' + [Environment]::NewLine + '    M3kArmRuntimeChurnHold();') 'arm runtime churn quarantine'

$vkBuildOld=@'
    if (ok && needs_build_vk)
    {
        Log("[feed] building: %ux%u backbuffer %s (Vulkan transport, depth reversed=%d)", w, h,
'@
$vkBuildNew=@'
    if (ok && needs_build_vk)
    {
        // We are past the existing create_delay hook grace on the fresh ReShade runtime.
        // This is the first safe point to touch the old NGX feature from the previous runtime.
        M3kReleaseDeferredRuntimeChurnFeature();
        Log("[feed] building: %ux%u backbuffer %s (Vulkan transport, depth reversed=%d)", w, h,
'@
$feed=Once $feed $vkBuildOld $vkBuildNew 'release deferred feature only after fresh-runtime grace'

[IO.File]::WriteAllText($nrPath,$nr,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
$verify=$nr+$vk+$feed
foreach($m in @('case 6: return "Custom Render Scale";','M3K-CUSTOM-SCALE:','Apply##M3KCustomScaleApply','NR Style##M3KNrStyle','Default\0Natural\0Cinematic','DLSSNR.Intensity','DLSSNR.LocalToneStrength','DLSSNR.LocalStructureStrength','DLSSNR.SkinStructureStrength','DLSSNR.UseAutoMask','DLSSNR.UICorrection','M3K_Sharpen.fx','M3kSyncSharpenUniform','Sharpening##M3KSharpness','M3K-DLAA-JITTER:','dlaa.InJitterOffsetX','M3K-SAFE-RESIZE:','M3kReleaseDeferredRuntimeChurnFeature','M3kRuntimeChurnHeld','runtime churn quarantine armed','Jitter Sequence##M3KJitterPhases','M3kComputeAutoJitterPhases','NGX Jitter Compensation##M3KJitterComp','M3K-JITTER-CAL:','Reset NR Advanced##M3KNrReset','Quality (67%)','FORCED %ux%u')){if($verify.IndexOf($m,[StringComparison]::Ordinal)-lt 0){throw "Missing verification marker: $m"}}
foreach($bad in @('if (profile > 5) profile = 2;','g_m3kMasterSavedProfile <= 5 ? g_m3kMasterSavedProfile : 2','savedProfileRaw <= 5 ? savedProfileRaw : 2','requestedSrProfile <= 5 ? requestedSrProfile : 2','g_m3kStartupPrimeInitialProfile <= 5','g_m3kSrProfileRequested > 5','if (profile < 1 || profile > 5) return false;')){if($verify.IndexOf($bad,[StringComparison]::Ordinal)-ge 0){throw "Stale SR bound remains: $bad"}}
Write-Host 'Next controls ready: Apply-only custom DLSS scale + NR style/tuning.'
