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
        const UINT rawScale=GetPrivateProfileIntW(L"M3K",L"CustomScalePercent",77,path);
        const UINT customScale=rawScale<10?10:(rawScale>100?100:rawScale);
        if(customScale!=g_m3kCustomScalePercent){
            g_m3kCustomScalePercent=customScale;
            if(g_m3kSrProfileRequested==6){g_m3kResolutionPlanProfile=0xFFFFFFFFu;g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;g_m3kResolutionConfirmedLogged=false;g_m3kSrNeedsReset=true;g_m3k.ResetHistory();}
        }
'@
$vk=Once $vk $poll $pollNew 'INI poll'
$vk=Once $vk 'g_m3k.Prepare(g_self, g.dev12, g.queue, g_m3kSrW, g_m3kSrH, g.create_flags, g_m3kNrPasses);' 'g_m3k.Prepare(g_self,g.dev12,g.queue,g_m3kSrW,g_m3kSrH,g.create_flags,g_m3kNrPasses,g_m3kNrStyle,g_m3kNrIntensity,g_m3kNrLocalTone,g_m3kNrLocalStructure,g_m3kNrSkinStructure,g_m3kNrAutoMask,g_m3kNrUiCorrection);' 'SR NR handoff'
$vk=Once $vk 'g_m3k.Prepare(g_self, g.dev12, g.queue, g.width, g.height, g.create_flags, g_m3kNrPasses);' 'g_m3k.Prepare(g_self,g.dev12,g.queue,g.width,g.height,g.create_flags,g_m3kNrPasses,g_m3kNrStyle,g_m3kNrIntensity,g_m3kNrLocalTone,g_m3kNrLocalStructure,g_m3kNrSkinStructure,g_m3kNrAutoMask,g_m3kNrUiCorrection);' 'native NR handoff'

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
struct M3kCustomContract{NVSDK_NGX_PerfQuality_Value q;const char *name;const char *hint;UINT optW,optH,minW,minH,maxW,maxH;};
static bool M3kFindCustomContract(UINT rw,UINT rh,UINT tw,UINT th,M3kCustomContract *out)
{
    struct C{NVSDK_NGX_PerfQuality_Value q;const char *name;const char *hint;};
    static const C cs[]={
        {NVSDK_NGX_PerfQuality_Value_MaxQuality,"Quality",NVSDK_NGX_Parameter_DLSS_Hint_Render_Preset_Quality},
        {NVSDK_NGX_PerfQuality_Value_Balanced,"Balanced",NVSDK_NGX_Parameter_DLSS_Hint_Render_Preset_Balanced},
        {NVSDK_NGX_PerfQuality_Value_MaxPerf,"Performance",NVSDK_NGX_Parameter_DLSS_Hint_Render_Preset_Performance},
        {NVSDK_NGX_PerfQuality_Value_UltraPerformance,"Ultra Performance",NVSDK_NGX_Parameter_DLSS_Hint_Render_Preset_UltraPerformance}};
    NVSDK_NGX_Parameter *caps=nullptr; const auto cr=NVSDK_NGX_D3D12_GetCapabilityParameters(&caps);
    if(NVSDK_NGX_FAILED(cr)||!caps)return false;
    bool found=false; UINT best=0xFFFFFFFFu; M3kCustomContract pick={};
    for(const auto &c:cs){unsigned ow=0,oh=0,maxw=0,maxh=0,minw=0,minh=0;float sharp=0.0f;
        const auto qr=NGX_DLSS_GET_OPTIMAL_SETTINGS(caps,tw,th,c.q,&ow,&oh,&maxw,&maxh,&minw,&minh,&sharp);
        if(NVSDK_NGX_FAILED(qr)||!ow||!oh||rw<minw||rw>maxw||rh<minh||rh>maxh)continue;
        const UINT dx=rw>ow?rw-ow:ow-rw,dy=rh>oh?rh-oh:oh-rh,score=dx+dy;
        if(!found||score<best){found=true;best=score;pick={c.q,c.name,c.hint,ow,oh,minw,minh,maxw,maxh};}}
    if(!found){Log("M3K-CUSTOM-SCALE: unsupported %ux%u -> %ux%u",rw,rh,tw,th);return false;}
    if(out)*out=pick; return true;
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
        if(!M3kFindCustomContract(rw,rh,targetW,targetH,nullptr))return false;
        *renderW=rw;*renderH=rh;Log("M3K-CUSTOM-SCALE: %u%% -> %ux%u",p,rw,rh);return true;
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

# Public setters/getters are inserted at the final accessor left by the master stages.
$api='static UINT M3kRequestedNrPasses() { return g_m3kNrPasses; }'
$apiNew=@'
static void M3kWritePublicUInt(const wchar_t *key,UINT value){wchar_t path[MAX_PATH]={};if(!GetModuleFileNameW(g_self,path,MAX_PATH))return;if(wchar_t *s=wcsrchr(path,L'\\')){*(s+1)=0;wcscat_s(path,L"m3k-nr.ini");wchar_t t[32]={};_snwprintf_s(t,_TRUNCATE,L"%u",value);WritePrivateProfileStringW(L"M3K",key,t,path);}}
static void M3kWritePublicFloat(const wchar_t *key,float value){wchar_t path[MAX_PATH]={};if(!GetModuleFileNameW(g_self,path,MAX_PATH))return;if(wchar_t *s=wcsrchr(path,L'\\')){*(s+1)=0;wcscat_s(path,L"m3k-nr.ini");wchar_t t[32]={};_snwprintf_s(t,_TRUNCATE,L"%.3f",static_cast<double>(value));WritePrivateProfileStringW(L"M3K",key,t,path);}}
static UINT M3kCustomScalePercent(){return g_m3kCustomScalePercent;} static bool M3kCustomScaleLastRejected(){return g_m3kCustomScaleRejected;}
static UINT M3kScaleW(UINT p){return g.width?(g.width*p+50u)/100u:0;} static UINT M3kScaleH(UINT p){return g.height?(g.height*p+50u)/100u:0;}
static void M3kApplyCustomScaleLive(UINT p){p=p<10?10:(p>100?100:p);if(p<100&&!M3kFindCustomContract(M3kScaleW(p),M3kScaleH(p),g.width,g.height,nullptr)){g_m3kCustomScaleRejected=true;return;}g_m3kCustomScaleRejected=false;g_m3kCustomScalePercent=p;M3kWritePublicUInt(L"CustomScalePercent",p);g_m3kResolutionPlanProfile=0xFFFFFFFFu;g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;g_m3kResolutionConfirmedLogged=false;g_m3kSrLatchedFail=false;g_m3kSrNeedsReset=true;g_m3k.ResetHistory();M3kRequestSrProfileLive(p>=100?0:6);}
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
        const char *items="DLAA Native\0Custom Ultra Quality (77%)\0Quality\0Balanced\0Performance\0Ultra Performance\0Custom Render Scale\0\0";
        if(ImGui::Combo("Mode##M3KSRProfile",&reconstruction,items)){if(reconstruction==6)M3kApplyCustomScaleLive(M3kCustomScalePercent());else M3kRequestSrProfileLive(static_cast<UINT>(reconstruction));}
        ImGui::EndDisabled();
        const int saved=static_cast<int>(M3kCustomScalePercent()); static int draft=-1,seen=-1;
        if(draft<10||draft>100){draft=saved;seen=saved;}else if(saved!=seen){if(draft==seen)draft=saved;seen=saved;}
        ImGui::BeginDisabled(!master); ImGui::SliderInt("Render Scale##M3KCustomScale",&draft,10,100,"%d%%");
        if(draft!=saved){ImGui::SameLine();if(ImGui::Button("Apply##M3KCustomScaleApply"))M3kApplyCustomScaleLive(static_cast<UINT>(draft));} ImGui::EndDisabled();
        if(draft>=100)ImGui::Text("100%% = DLAA Native (%u x %u)",M3kScaleW(100),M3kScaleH(100));else ImGui::Text("Custom preview: %d%% = %u x %u -> %u x %u",draft,M3kScaleW(static_cast<UINT>(draft)),M3kScaleH(static_cast<UINT>(draft)),g.width,g.height);
        if(M3kCustomScaleLastRejected())ImGui::TextColored(ImVec4(1.0f,0.45f,0.35f,1.0f),"Unsupported by DLSS at this output; current mode kept.");
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
            ImGui::Spacing(); const UINT requested=M3kRequestedNrPasses(); ImGui::TextUnformatted("Neural Rendering passes");
            for(UINT p=1;p<=5;++p){if(p>1)ImGui::SameLine();char label[24]={};_snprintf_s(label,sizeof(label),_TRUNCATE,"%u##M3KPass",p);if(ImGui::RadioButton(label,requested==p))M3kRequestNrPassesLive(p);} ImGui::Text("Active passes: %u",M3kActiveNrPasses()); ImGui::EndDisabled();}
        if(ImGui::CollapsingHeader("Diagnostics##M3KDiagnostics")){ImGui::Text("Requested render: %u x %u",M3kDesiredRenderWidth(),M3kDesiredRenderHeight());ImGui::Text("DXVK source: %u x %u",M3kCurrentSourceWidth(),M3kCurrentSourceHeight());ImGui::Text("Output: %u x %u",g.width,g.height);ImGui::Text("Saved custom scale: %u%%",M3kCustomScalePercent());ImGui::Text("NR style=%u intensity=%.2f tone=%.2f structure=%.2f skin=%.2f",M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested());}
        ImGui::Separator();
    }
'@
$feed=$feed.Substring(0,$start)+$ui+$feed.Substring($end)

[IO.File]::WriteAllText($nrPath,$nr,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
$verify=$nr+$vk+$feed
foreach($m in @('case 6: return "Custom Render Scale";','M3K-CUSTOM-SCALE:','Apply##M3KCustomScaleApply','NR Style##M3KNrStyle','Default\0Natural\0Cinematic','DLSSNR.Intensity','DLSSNR.LocalToneStrength','DLSSNR.LocalStructureStrength','DLSSNR.SkinStructureStrength','DLSSNR.UseAutoMask','DLSSNR.UICorrection')){if($verify.IndexOf($m,[StringComparison]::Ordinal)-lt 0){throw "Missing verification marker: $m"}}
foreach($bad in @('if (profile > 5) profile = 2;','g_m3kMasterSavedProfile <= 5 ? g_m3kMasterSavedProfile : 2','savedProfileRaw <= 5 ? savedProfileRaw : 2','requestedSrProfile <= 5 ? requestedSrProfile : 2','g_m3kStartupPrimeInitialProfile <= 5','g_m3kSrProfileRequested > 5','if (profile < 1 || profile > 5) return false;')){if($verify.IndexOf($bad,[StringComparison]::Ordinal)-ge 0){throw "Stale SR bound remains: $bad"}}
Write-Host 'Next controls ready: Apply-only custom DLSS scale + NR style/tuning.'
