[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if($count-ne 1){throw "v1.2.0 stage $Label expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
if(-not(Test-Path -LiteralPath $vkPath)){throw "Missing generated source: $vkPath"}
if(-not(Test-Path -LiteralPath $FeederSource)){throw "Missing feeder source: $FeederSource"}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

$feed=Once $feed 'extern "C" __declspec(dllexport) const char *NAME = "DLSS 5 Feed " FEED_VERSION;' 'extern "C" __declspec(dllexport) const char *NAME = "GTA IV Scaling 1.2.0";' 'add-on display name'

$descOld=@'
extern "C" __declspec(dllexport) const char *DESCRIPTION =
    "Feeds DLSS 5 neural rendering with ReShade's depth and estimated motion vectors in D3D11, "
    "D3D12, Vulkan and OpenGL games without DLSS: runs a real DLSS DLAA pass where the DLSS 5 add-on "
    "hooks in (a private D3D12 device for D3D11, Vulkan and OpenGL games, the game's own device for "
    "D3D12) and writes the result back into the frame.Needs DLSS5_Feed.fx and a motion-vector provider (DRME, qUINT, Launchpad, VORT or LumeniteFX; pick it with the DLSS5_MV_PROVIDER definition). "
'@
$descNew=@'
extern "C" __declspec(dllexport) const char *DESCRIPTION =
    "GTA IV Scaling: native rendering, NVIDIA DLAA/DLSS and AMD FidelityFX FSR in one live-selectable GTA IV pipeline. "
    "The installer exposes NVIDIA scaling only on detected NVIDIA RTX systems; FSR remains available on all supported GPUs. "
'@
$feed=Once $feed $descOld $descNew 'add-on description'
$feed=$feed.Replace('GTA IV Reconstruction','GTA IV Scaling')

$stateOld='static UINT g_m3kScalingTechnologyRequested=1;'
$stateNew=@'
static UINT g_m3kScalingTechnologyRequested=1;
static bool g_m3kNvidiaRtxAvailable=true;
static bool M3kNvidiaRtxAvailable(){return g_m3kNvidiaRtxAvailable;}
'@
$vk=Once $vk $stateOld $stateNew 'RTX capability state'

$nameOld=@'
static const char *M3kScalingTechnologyName(UINT tech)
{
    switch(tech){case 0:return "Off";case 2:return "AMD - FSR";default:return "NVIDIA - DLAA / DLSS 4.5";}
}
'@
$nameNew=@'
static const char *M3kScalingTechnologyName(UINT tech)
{
    switch(tech){case 0:return "Off - Native";case 2:return "AMD FidelityFX FSR";default:return "NVIDIA DLAA / DLSS";}
}
'@
$vk=Once $vk $nameOld $nameNew 'public backend names'

$requestOld=@'
static void M3kRequestScalingTechnologyLive(UINT tech)
{
    if(tech>2)tech=1;
'@
$requestNew=@'
static void M3kRequestScalingTechnologyLive(UINT tech)
{
    if(tech>2)tech=1;
    if(tech==1u&&!g_m3kNvidiaRtxAvailable)
    {
        Log("GTA IV Scaling: NVIDIA DLAA/DLSS request rejected because installer capability says NVIDIA RTX is unavailable");
        g_m3kScalingTransitionLastFailed=true;
        return;
    }
'@
$vk=Once $vk $requestOld $requestNew 'NVIDIA capability live gate'

$pollOld=@'
        wchar_t m3kTechText[16]={};
        GetPrivateProfileStringW(L"M3K",L"ScalingTechnology",L"",m3kTechText,16,path);
        UINT m3kTech=1u;
'@
$pollNew=@'
        g_m3kNvidiaRtxAvailable=GetPrivateProfileIntW(L"M3K",L"NvidiaRtxAvailable",1,path)!=0;
        wchar_t m3kTechText[16]={};
        GetPrivateProfileStringW(L"M3K",L"ScalingTechnology",L"",m3kTechText,16,path);
        UINT m3kTech=g_m3kNvidiaRtxAvailable?1u:2u;
'@
$vk=Once $vk $pollOld $pollNew 'capability poll'

$compatOld=@'
        }else{
            // Compatibility with P1-P6 test INIs which used only FSRProof.
            m3kTech=GetPrivateProfileIntW(L"M3K",L"FSRProof",0,path)!=0?2u:1u;
        }
        if(!g_m3kScalingTechnologyInitialized){
'@
$compatNew=@'
        }else{
            // Compatibility with P1-P6 test INIs which used only FSRProof.
            m3kTech=GetPrivateProfileIntW(L"M3K",L"FSRProof",0,path)!=0?2u:(g_m3kNvidiaRtxAvailable?1u:2u);
        }
        if(!g_m3kNvidiaRtxAvailable&&m3kTech==1u)
        {
            m3kTech=2u;
            WritePrivateProfileStringW(L"M3K",L"ScalingTechnology",L"2",path);
            Log("GTA IV Scaling: NVIDIA RTX unavailable; startup selection constrained to AMD FidelityFX FSR");
        }
        if(!g_m3kScalingTechnologyInitialized){
'@
$vk=Once $vk $compatOld $compatNew 'startup capability coercion'

$uiOld=@'
        int technology=static_cast<int>(M3kScalingTechnologyRequested());
        const char *technologyItems="Off\0NVIDIA - DLAA / DLSS 4.5\0AMD - FSR\0\0";
        ImGui::TextUnformatted("Scaling Technology");
        if(ImGui::Combo("Technology##M3KScalingTechnology",&technology,technologyItems))
            M3kRequestScalingTechnologyLive(static_cast<UINT>(technology));
'@
$uiNew=@'
        ImGui::TextUnformatted("Scaling Technology");
        if(M3kNvidiaRtxAvailable())
        {
            int technology=static_cast<int>(M3kScalingTechnologyRequested());
            const char *technologyItems="Off - Native\0NVIDIA DLAA / DLSS\0AMD FidelityFX FSR\0\0";
            if(ImGui::Combo("Technology##M3KScalingTechnology",&technology,technologyItems))
                M3kRequestScalingTechnologyLive(static_cast<UINT>(technology));
        }
        else
        {
            int technology=M3kScalingTechnologyRequested()==2u?1:0;
            const char *technologyItems="Off - Native\0AMD FidelityFX FSR\0\0";
            if(ImGui::Combo("Technology##M3KScalingTechnology",&technology,technologyItems))
                M3kRequestScalingTechnologyLive(technology==1?2u:0u);
        }
'@
$feed=Once $feed $uiOld $uiNew 'capability filtered selector'

$diagOld='            ImGui::Text("Active backend: %s",M3kScalingTechnologyName(M3kScalingTechnologyActive()));'
$diagNew=@'
            ImGui::Text("Active backend: %s",M3kScalingTechnologyName(M3kScalingTechnologyActive()));
            ImGui::Text("NVIDIA RTX capability: %s",M3kNvidiaRtxAvailable()?"available":"not available - NVIDIA option hidden");
'@
$feed=Once $feed $diagOld $diagNew 'capability diagnostics'

foreach($marker in @(
    'GTA IV Scaling 1.2.0',
    'GTA IV Scaling',
    'NvidiaRtxAvailable',
    'NVIDIA RTX unavailable; startup selection constrained to AMD FidelityFX FSR',
    'NVIDIA RTX capability: %s',
    'AMD FidelityFX FSR'
)){
    if(($vk+$feed).IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "v1.2.0 marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'v1.2.0 GTA IV Scaling identity + installer-driven RTX capability filtering applied.'
