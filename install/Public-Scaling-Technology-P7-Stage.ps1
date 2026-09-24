[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR P7 stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
foreach($p in @($vkPath,$FeederSource)){if(-not(Test-Path -LiteralPath $p)){throw "Missing generated source: $p"}}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

# ---------------------------------------------------------------------------
# P7: explicit technology selection.
# 0 = Off/raw
# 1 = NVIDIA DLAA/DLSS 4.5
# 2 = AMD FSR
#
# Backend changes are intentionally restart-gated in P7. The requested selection is
# persisted immediately, but all runtime dispatch/session decisions use the backend
# captured at the first config poll / Vulkan session open. P8 can add live switching
# only after the selector itself is hardware-proven.
# ---------------------------------------------------------------------------

$stateAnchor='static UINT g_m3kFsrScalePermille=667; // P2 fixed FSR Quality ~= 2/3 input scale'
$stateNew=@'
static UINT g_m3kScalingTechnologyActive=1;    // 0 Off, 1 NVIDIA, 2 AMD
static UINT g_m3kScalingTechnologyRequested=1;
static bool g_m3kScalingTechnologyInitialized=false;
static bool g_m3kScalingTechnologyRestartPending=false;
static bool g_m3kScalingOffTransitionIssued=false;
static UINT g_m3kFsrScalePermille=667; // independent AMD/FSR scale; NVIDIA settings remain separate
'@
$vk=Once $vk $stateAnchor $stateNew 'backend state'

# Public helpers live after M3kWritePublicUInt/M3kWritePublicFloat are available.
$apiAnchor='static UINT M3kCustomScalePercent(){return g_m3kCustomScalePercent;} static bool M3kCustomScaleLastRejected(){return g_m3kCustomScaleRejected;}'
$apiNew=@'
static const char *M3kScalingTechnologyName(UINT tech)
{
    switch(tech){case 0:return "Off";case 2:return "AMD - FSR";default:return "NVIDIA - DLAA / DLSS 4.5";}
}
static UINT M3kScalingTechnologyActive(){return g_m3kScalingTechnologyActive;}
static UINT M3kScalingTechnologyRequested(){return g_m3kScalingTechnologyRequested;}
static bool M3kScalingTechnologyRestartPending(){return g_m3kScalingTechnologyRestartPending;}
static void M3kRequestScalingTechnologyRestart(UINT tech)
{
    if(tech>2)tech=1;
    g_m3kScalingTechnologyRequested=tech;
    g_m3kScalingTechnologyRestartPending=tech!=g_m3kScalingTechnologyActive;
    M3kWritePublicUInt(L"ScalingTechnology",tech);
    Log("M3K-P7: scaling technology requested=%s active=%s restart=%s",
        M3kScalingTechnologyName(tech),M3kScalingTechnologyName(g_m3kScalingTechnologyActive),
        g_m3kScalingTechnologyRestartPending?"REQUIRED":"no");
}
static UINT M3kFsrScalePermilleRequested(){return g_m3kFsrScalePermille;}
static UINT M3kFsrScalePercentRounded(){return (g_m3kFsrScalePermille+5u)/10u;}
static UINT M3kFsrScaleW(UINT percent){return g.width?(g.width*percent+50u)/100u:0;}
static UINT M3kFsrScaleH(UINT percent){return g.height?(g.height*percent+50u)/100u:0;}
static int M3kFsrPresetChoice()
{
    const UINT p=g_m3kFsrScalePermille;
    if(p==1000)return 0;if(p==770)return 1;if(p==667)return 2;
    if(p==590)return 3;if(p==500)return 4;if(p==330||p==333)return 5;
    return 6;
}
static void M3kRequestFsrScalePermilleLive(UINT permille)
{
    if(permille<100)permille=100;if(permille>1000)permille=1000;
    if(permille==g_m3kFsrScalePermille)return;
    g_m3kFsrScalePermille=permille;
    M3kWritePublicUInt(L"FSRScalePermille",permille);
    g_m3kResolutionPlanProfile=0xFFFFFFFFu;g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;
    g_m3kResolutionConfirmedLogged=false;g_m3kFsrPlannerLogged=false;g_m3kFsrNeedsReset=true;
    g_m3k.ResetHistory();
    Log("M3K-P7: AMD FSR scale requested %.1f%%; independent FSR render plan invalidated",
        static_cast<double>(permille)/10.0);
}
static void M3kRequestFsrScalePercentLive(UINT percent)
{
    if(percent<10)percent=10;if(percent>100)percent=100;
    M3kRequestFsrScalePermilleLive(percent*10u);
}

static UINT M3kCustomScalePercent(){return g_m3kCustomScalePercent;} static bool M3kCustomScaleLastRejected(){return g_m3kCustomScaleRejected;}
'@
$vk=Once $vk $apiAnchor $apiNew 'public selector API'

# Capture active backend once. Later INI edits update only "requested" and show restart pending.
$pollAnchor='        const bool resumeMasterOnLaunch = GetPrivateProfileIntW(L"M3K", L"MasterEnabled", 1, path) == 0;'
$pollNew=@'
        wchar_t m3kTechText[16]={};
        GetPrivateProfileStringW(L"M3K",L"ScalingTechnology",L"",m3kTechText,16,path);
        UINT m3kTech=1u;
        if(m3kTechText[0]){
            wchar_t *m3kTechEnd=nullptr;
            const unsigned long parsed=wcstoul(m3kTechText,&m3kTechEnd,10);
            m3kTech=(m3kTechEnd!=m3kTechText&&parsed<=2ul)?static_cast<UINT>(parsed):1u;
        }else{
            // Compatibility with P1-P6 test INIs which used only FSRProof.
            m3kTech=GetPrivateProfileIntW(L"M3K",L"FSRProof",0,path)!=0?2u:1u;
        }
        if(!g_m3kScalingTechnologyInitialized){
            g_m3kScalingTechnologyActive=m3kTech;
            g_m3kScalingTechnologyRequested=m3kTech;
            g_m3kScalingTechnologyRestartPending=false;
            g_m3kScalingTechnologyInitialized=true;
            g_m3kScalingOffTransitionIssued=false;
            Log("M3K-P7: active scaling technology captured at launch: %s",M3kScalingTechnologyName(m3kTech));
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

        const bool resumeMasterOnLaunch = GetPrivateProfileIntW(L"M3K", L"MasterEnabled", 1, path) == 0;
'@
$vk=Once $vk $pollAnchor $pollNew 'active backend capture'

# FSR runtime selection is tied to the launch-captured backend, not the mutable requested INI.
$fsrPollOld='        const bool fsrProof = GetPrivateProfileIntW(L"M3K", L"FSRProof", 0, path) != 0;'
$fsrPollNew='        const bool fsrProof = g_m3kScalingTechnologyActive==2u;'
$vk=Once $vk $fsrPollOld $fsrPollNew 'FSR active backend poll'

# P3 must choose AMD native Vulkan before any D3D12/NGX creation. Read the persistent
# selector directly because this runs before m3k_vk.h config polling has initialized.
$sessionOld=@'
    return GetPrivateProfileIntW(L"M3K",L"FSRProof",0,path)!=0;
'@
$sessionNew=@'
    wchar_t techText[16]={};
    GetPrivateProfileStringW(L"M3K",L"ScalingTechnology",L"",techText,16,path);
    if(techText[0]){
        wchar_t *end=nullptr;const unsigned long tech=wcstoul(techText,&end,10);
        if(end!=techText)return tech==2ul;
    }
    return GetPrivateProfileIntW(L"M3K",L"FSRProof",0,path)!=0;
'@
$feed=Once $feed $sessionOld $sessionNew 'session-open selector'

# Replace the final public panel. Backend-specific controls are mutually exclusive.
$mark='    if (ImGui::CollapsingHeader("GTA IV DLSS", ImGuiTreeNodeFlags_DefaultOpen))'
$start=$feed.IndexOf($mark,[StringComparison]::Ordinal)
if($start-lt 0){throw 'P7 final UI marker missing'}
$brace=$feed.IndexOf('{',$start)
if($brace-lt 0){throw 'P7 UI opening brace missing'}
$depth=0;$end=-1
for($i=$brace;$i-lt $feed.Length;$i++){
    if($feed[$i]-eq '{'){$depth++}
    elseif($feed[$i]-eq '}'){$depth--;if($depth-eq 0){$end=$i+1;break}}
}
if($end-lt 0){throw 'P7 UI closing brace missing'}

$ui=@'
    if (ImGui::CollapsingHeader("GTA IV Reconstruction", ImGuiTreeNodeFlags_DefaultOpen))
    {
        int technology=static_cast<int>(M3kScalingTechnologyRequested());
        const char *technologyItems="Off\0NVIDIA - DLAA / DLSS 4.5\0AMD - FSR\0\0";
        ImGui::TextUnformatted("Scaling Technology");
        if(ImGui::Combo("Technology##M3KScalingTechnology",&technology,technologyItems))
            M3kRequestScalingTechnologyRestart(static_cast<UINT>(technology));
        ImGui::Text("Active this session: %s",M3kScalingTechnologyName(M3kScalingTechnologyActive()));
        if(M3kScalingTechnologyRestartPending())
            ImGui::TextColored(ImVec4(1.0f,0.78f,0.25f,1.0f),
                "Restart GTA IV to switch to %s.",M3kScalingTechnologyName(M3kScalingTechnologyRequested()));

        const UINT activeTech=M3kScalingTechnologyActive();

        if(activeTech==0u)
        {
            ImGui::Separator();
            if(M3kMasterNativePassthroughReady())
                ImGui::TextColored(ImVec4(0.35f,1.0f,0.45f,1.0f),"Off - native raw rendering");
            else
                ImGui::TextColored(ImVec4(1.0f,0.78f,0.25f,1.0f),"Off - returning GTA to native raw rendering...");
            ImGui::TextWrapped("No DLAA, DLSS, FSR or Neural Rendering evaluate is used after the safe native transition completes.");
        }
        else if(activeTech==1u)
        {
            const bool master=M3kMasterEnabledRequested();
            ImGui::Separator(); ImGui::TextUnformatted("NVIDIA Reconstruction");
            int reconstruction=static_cast<int>(M3kRequestedSrProfile());if(reconstruction<0||reconstruction>6)reconstruction=2;
            const char *items="DLAA Native (100%)\0Custom Ultra Quality (77%)\0Quality (67%)\0Balanced (58%)\0Performance (50%)\0Ultra Performance (33%)\0Custom Render Scale\0\0";
            if(ImGui::Combo("Mode##M3KSRProfile",&reconstruction,items)){
                if(reconstruction==6)M3kApplyCustomScaleLive(M3kCustomScalePercent());
                else M3kRequestSrProfileLive(static_cast<UINT>(reconstruction));
            }

            const int saved=static_cast<int>(M3kCustomScalePercent());static int draft=-1,seen=-1;
            if(draft<10||draft>100){draft=saved;seen=saved;}else if(saved!=seen){if(draft==seen)draft=saved;seen=saved;}
            ImGui::SliderInt("Render Scale##M3KCustomScale",&draft,10,100,"%d%%");
            if(draft!=saved){ImGui::SameLine();if(ImGui::Button("Apply##M3KCustomScaleApply"))M3kApplyCustomScaleLive(static_cast<UINT>(draft));}
            if(draft>=100)ImGui::Text("100%% = DLAA Native (%u x %u)",M3kScaleW(100),M3kScaleH(100));
            else ImGui::Text("Custom preview: %d%% = %u x %u -> %u x %u",draft,M3kScaleW(static_cast<UINT>(draft)),M3kScaleH(static_cast<UINT>(draft)),g.width,g.height);
            if(M3kCustomScaleLastRejected())ImGui::TextColored(ImVec4(1.0f,0.45f,0.35f,1.0f),"NVIDIA rejected feature creation at this forced scale; previous reconstruction is still displayed.");

            static float sharpDraft=-1.0f;if(sharpDraft<0.0f)sharpDraft=M3kSharpnessRequested();
            if(ImGui::SliderFloat("NVIDIA Sharpening##M3KSharpness",&sharpDraft,0.0f,1.5f,"%.2f"))M3kRequestSharpnessLive(sharpDraft);
            ImGui::TextDisabled("0.00 = off   0.35 = mild   0.75 = strong   1.50 = extreme");
            ImGui::Text("Current: %s",M3kSrProfileName(M3kAppliedSrProfile()));
            if(master&&M3kAppliedSrProfile()!=M3kRequestedSrProfile())
                ImGui::TextColored(ImVec4(1.0f,0.78f,0.25f,1.0f),"Applying %s...",M3kSrProfileName(M3kRequestedSrProfile()));

            ImGui::Separator();ImGui::TextUnformatted("NVIDIA Neural Rendering");
            bool nr=M3kNrEnabledRequested();
            if(ImGui::Checkbox("Enable Neural Rendering##M3KNrEnabled",&nr))M3kRequestNrEnabledLive(nr);

            if(ImGui::CollapsingHeader("Advanced##M3KAdvanced")){
                ImGui::TextUnformatted("Temporal AA");
                M3kSyncJitterPhasesLive();
                int jitterChoice=0;const UINT jitterMode=M3kJitterModeRequested();
                if(jitterMode==8)jitterChoice=1;else if(jitterMode==16)jitterChoice=2;else if(jitterMode==32)jitterChoice=3;
                const char *jitterItems="Auto\0" "8 phases\0" "16 phases\0" "32 phases\0\0";
                if(ImGui::Combo("Jitter Sequence##M3KJitterPhases",&jitterChoice,jitterItems)){const UINT modes[4]={0u,8u,16u,32u};M3kRequestJitterModeLive(modes[jitterChoice]);}
                ImGui::TextDisabled("Effective: %u phases%s",M3kJitterEffectivePhases(),M3kJitterModeRequested()==0?" (Auto)":"");
                ImGui::TextDisabled("NGX compensation: +1/+1 (GTA IV calibrated)");

                ImGui::Spacing();ImGui::Separator();ImGui::TextUnformatted("Neural Rendering");
                ImGui::BeginDisabled(!nr);
                int style=static_cast<int>(M3kNrStyleRequested());const char *styles="Default\0Natural\0Cinematic\0\0";
                if(ImGui::Combo("NR Style##M3KNrStyle",&style,styles))M3kRequestNrTuningLive(static_cast<UINT>(style),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
                static float i=-1,t=-1,s=-1,skin=-1;if(i<0)i=M3kNrIntensityRequested();if(t<0)t=M3kNrLocalToneRequested();if(s<0)s=M3kNrLocalStructureRequested();if(skin<0)skin=M3kNrSkinStructureRequested();
                ImGui::SliderFloat("Intensity##M3KNrIntensity",&i,0.0f,2.0f,"%.2f");if(ImGui::IsItemDeactivatedAfterEdit())M3kRequestNrTuningLive(M3kNrStyleRequested(),i,M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
                ImGui::SliderFloat("Local Tone##M3KNrTone",&t,0.0f,2.0f,"%.2f");if(ImGui::IsItemDeactivatedAfterEdit())M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),t,M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
                ImGui::SliderFloat("Local Structure##M3KNrStructure",&s,0.0f,2.0f,"%.2f");if(ImGui::IsItemDeactivatedAfterEdit())M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),s,M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
                ImGui::SliderFloat("Skin Structure##M3KNrSkin",&skin,0.0f,2.0f,"%.2f");if(ImGui::IsItemDeactivatedAfterEdit())M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),skin,M3kNrAutoMaskRequested(),M3kNrUiCorrectionRequested());
                bool mask=M3kNrAutoMaskRequested();if(ImGui::Checkbox("Auto Mask##M3KNrAutoMask",&mask))M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),mask,M3kNrUiCorrectionRequested());
                bool ui=M3kNrUiCorrectionRequested();if(ImGui::Checkbox("UI Correction##M3KNrUiCorrection",&ui))M3kRequestNrTuningLive(M3kNrStyleRequested(),M3kNrIntensityRequested(),M3kNrLocalToneRequested(),M3kNrLocalStructureRequested(),M3kNrSkinStructureRequested(),M3kNrAutoMaskRequested(),ui);
                if(ImGui::Button("Reset NR Advanced##M3KNrReset")){i=1.0f;t=1.0f;s=1.0f;skin=1.0f;M3kRequestNrTuningLive(0,1.0f,1.0f,1.0f,1.0f,true,false);}
                ImGui::Spacing();const UINT requested=M3kRequestedNrPasses();ImGui::TextUnformatted("Neural Rendering passes");
                for(UINT p=1;p<=5;++p){if(p>1)ImGui::SameLine();char label[24]={};_snprintf_s(label,sizeof(label),_TRUNCATE,"%u##M3KPass",p);if(ImGui::RadioButton(label,requested==p))M3kRequestNrPassesLive(p);}
                ImGui::Text("Active passes: %u",M3kActiveNrPasses());ImGui::EndDisabled();
            }
        }
        else
        {
            ImGui::Separator();ImGui::TextUnformatted("AMD FSR");
            int fsrPreset=M3kFsrPresetChoice();
            const char *fsrItems="Native AA (100%)\0Ultra Quality (77%)\0Quality (66.7%)\0Balanced (59%)\0Performance (50%)\0Ultra Performance (33%)\0Custom Render Scale\0\0";
            if(ImGui::Combo("Mode##M3KFSRPreset",&fsrPreset,fsrItems)){
                const UINT scales[6]={1000u,770u,667u,590u,500u,330u};
                if(fsrPreset>=0&&fsrPreset<6)M3kRequestFsrScalePermilleLive(scales[fsrPreset]);
            }

            const int fsrSaved=static_cast<int>(M3kFsrScalePercentRounded());static int fsrDraft=-1,fsrSeen=-1;
            if(fsrDraft<10||fsrDraft>100){fsrDraft=fsrSaved;fsrSeen=fsrSaved;}else if(fsrSaved!=fsrSeen){if(fsrDraft==fsrSeen)fsrDraft=fsrSaved;fsrSeen=fsrSaved;}
            ImGui::SliderInt("Render Scale##M3KFSRCustomScale",&fsrDraft,10,100,"%d%%");
            if(static_cast<UINT>(fsrDraft)!=fsrSaved){ImGui::SameLine();if(ImGui::Button("Apply##M3KFSRCustomScaleApply"))M3kRequestFsrScalePercentLive(static_cast<UINT>(fsrDraft));}
            ImGui::Text("FSR input: %.1f%%  %u x %u -> %u x %u",
                static_cast<double>(M3kFsrScalePermilleRequested())/10.0,
                g_m3kDesiredRenderW,g_m3kDesiredRenderH,g.width,g.height);
            ImGui::TextDisabled("RCAS sharpening: OFF in P7 (separate AMD control is the next backend stage).");

            if(ImGui::CollapsingHeader("Advanced##M3KAdvanced")){
                M3kSyncJitterPhasesLive();
                ImGui::Text("Temporal jitter: AMD auto");
                ImGui::Text("Effective jitter phases: %u",M3kJitterEffectivePhases());
                ImGui::Text("Camera: near 0.05  far 1500  vertical FOV 45 deg");
                ImGui::Text("Motion vectors: pixel-space current -> previous, scale=(1,1)");
            }
        }

        if(ImGui::CollapsingHeader("Diagnostics##M3KDiagnostics")){
            ImGui::Text("Active backend: %s",M3kScalingTechnologyName(M3kScalingTechnologyActive()));
            ImGui::Text("Requested backend: %s",M3kScalingTechnologyName(M3kScalingTechnologyRequested()));
            ImGui::Text("Requested render: %u x %u",M3kDesiredRenderWidth(),M3kDesiredRenderHeight());
            ImGui::Text("DXVK source: %u x %u",M3kCurrentSourceWidth(),M3kCurrentSourceHeight());
            ImGui::Text("Output: %u x %u",g.width,g.height);
            ImGui::Text("Jitter effective: %u phases",M3kJitterEffectivePhases());
        }
        ImGui::Separator();
    }
'@
$feed=$feed.Substring(0,$start)+$ui+$feed.Substring($end)

foreach($marker in @(
    'ScalingTechnology',
    'M3K-P7: active scaling technology captured at launch',
    'M3kRequestScalingTechnologyRestart',
    'GTA IV Reconstruction',
    'NVIDIA - DLAA / DLSS 4.5',
    'AMD - FSR',
    'RCAS sharpening: OFF in P7',
    'const bool fsrProof = g_m3kScalingTechnologyActive==2u;',
    'Restart GTA IV to switch to'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0 -and
       $feed.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR P7 verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'FSR-P7 selector applied: Off / NVIDIA / AMD with restart-gated backend changes and independent FSR scale.'
