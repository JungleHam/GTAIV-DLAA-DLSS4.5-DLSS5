[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR P8 stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
foreach($p in @($vkPath,$FeederSource)){if(-not(Test-Path -LiteralPath $p)){throw "Missing generated source: $p"}}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

# Independent AMD RCAS state. NVIDIA sharpening remains the existing Sharpness key/stage.
$stateOld='static bool g_m3kFsrPlannerLogged=false;'
$stateNew=@'
static bool g_m3kFsrPlannerLogged=false;
static float g_m3kFsrSharpness=0.0f;
'@
$vk=Once $vk $stateOld $stateNew 'AMD RCAS state'

$pollOld=@'
        if(fsrScalePermille<100)fsrScalePermille=100;
        if(fsrScalePermille>1000)fsrScalePermille=1000;
'@
$pollNew=@'
        if(fsrScalePermille<100)fsrScalePermille=100;
        if(fsrScalePermille>1000)fsrScalePermille=1000;
        float fsrSharpness=M3kReadPublicFloat(path,L"FSRSharpness",0.0f);
        if(fsrSharpness<0.0f)fsrSharpness=0.0f;
        if(fsrSharpness>1.0f)fsrSharpness=1.0f;
'@
$vk=Once $vk $pollOld $pollNew 'RCAS INI read'

$nonVkOld='        const UINT fsrScalePermille=667u;'
$nonVkNew=@'
        const UINT fsrScalePermille=667u;
        const float fsrSharpness=0.0f;
'@
$vk=Once $vk $nonVkOld $nonVkNew 'RCAS non-Vulkan default'

$assignOld=@'
        if(fsrScalePermille!=g_m3kFsrScalePermille){
            g_m3kFsrScalePermille=fsrScalePermille;
            g_m3kResolutionPlanProfile=0xFFFFFFFFu;g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;
            g_m3kResolutionConfirmedLogged=false;g_m3kFsrPlannerLogged=false;g_m3kFsrNeedsReset=true;
            Log("M3K-FSR-P2: independent FSR scale changed to %.1f%%; render plan invalidated",
                static_cast<double>(g_m3kFsrScalePermille)/10.0);
        }
        g_m3kFsrProofRequested=fsrProof;
'@
$assignNew=@'
        if(fsrScalePermille!=g_m3kFsrScalePermille){
            g_m3kFsrScalePermille=fsrScalePermille;
            g_m3kResolutionPlanProfile=0xFFFFFFFFu;g_m3kResolutionPlanOutW=g_m3kResolutionPlanOutH=0;
            g_m3kResolutionConfirmedLogged=false;g_m3kFsrPlannerLogged=false;g_m3kFsrNeedsReset=true;
            Log("M3K-FSR-P2: independent FSR scale changed to %.1f%%; render plan invalidated",
                static_cast<double>(g_m3kFsrScalePermille)/10.0);
        }
        if(fsrSharpness!=g_m3kFsrSharpness){
            g_m3kFsrSharpness=fsrSharpness;
            Log("M3K-FSR-P8: AMD RCAS sharpness changed to %.3f (%s)",
                static_cast<double>(g_m3kFsrSharpness),g_m3kFsrSharpness>0.0001f?"enabled":"off");
        }
        g_m3kFsrProofRequested=fsrProof;
'@
$vk=Once $vk $assignOld $assignNew 'RCAS state commit'

$dispatchOld=@'
    d.frameTimeMs=M3kFsrFrameTimeMs();
    d.preExposure=1.0f;
    d.reset=reset!=0||g_m3kFsrNeedsReset;
'@
$dispatchNew=@'
    d.frameTimeMs=M3kFsrFrameTimeMs();
    d.preExposure=1.0f;
    d.enableSharpening=g_m3kFsrSharpness>0.0001f;
    d.sharpness=g_m3kFsrSharpness;
    d.reset=reset!=0||g_m3kFsrNeedsReset;
'@
$vk=Once $vk $dispatchOld $dispatchNew 'RCAS dispatch handoff'

$apiOld=@'
static void M3kRequestFsrScalePercentLive(UINT percent)
{
    if(percent<10)percent=10;if(percent>100)percent=100;
    M3kRequestFsrScalePermilleLive(percent*10u);
}
'@
$apiNew=@'
static void M3kRequestFsrScalePercentLive(UINT percent)
{
    if(percent<10)percent=10;if(percent>100)percent=100;
    M3kRequestFsrScalePermilleLive(percent*10u);
}
static float M3kFsrSharpnessRequested(){return g_m3kFsrSharpness;}
static void M3kRequestFsrSharpnessLive(float value)
{
    if(value<0.0f)value=0.0f;if(value>1.0f)value=1.0f;
    g_m3kFsrSharpness=value;
    M3kWritePublicFloat(L"FSRSharpness",value);
    Log("M3K-FSR-P8: UI requested AMD RCAS sharpness %.3f (%s)",
        static_cast<double>(value),value>0.0001f?"enabled":"off");
}
'@
$vk=Once $vk $apiOld $apiNew 'RCAS public API'

$uiOld='            ImGui::TextDisabled("RCAS sharpening: OFF in P7 (separate AMD control is the next backend stage).");'
$uiNew=@'
            static float fsrSharpDraft=-1.0f;if(fsrSharpDraft<0.0f)fsrSharpDraft=M3kFsrSharpnessRequested();
            if(ImGui::SliderFloat("AMD RCAS Sharpening##M3KFSRSharpness",&fsrSharpDraft,0.0f,1.0f,"%.2f"))
                M3kRequestFsrSharpnessLive(fsrSharpDraft);
            ImGui::TextDisabled("0.00 = off   0.25 = mild   0.50 = medium   1.00 = maximum");
'@
$feed=Once $feed $uiOld $uiNew 'RCAS UI'

$diagOld='            ImGui::Text("Motion vectors: pixel-space current -> previous, scale=(1,1)");'
$diagNew=@'
            ImGui::Text("Motion vectors: pixel-space current -> previous, scale=(1,1)");
            ImGui::Text("RCAS: %s sharpness=%.2f",M3kFsrSharpnessRequested()>0.0001f?"ON":"OFF",M3kFsrSharpnessRequested());
'@
$feed=Once $feed $diagOld $diagNew 'RCAS diagnostics'

foreach($marker in @(
    'g_m3kFsrSharpness=0.0f',
    'FSRSharpness',
    'd.enableSharpening=g_m3kFsrSharpness>0.0001f',
    'AMD RCAS Sharpening##M3KFSRSharpness',
    'M3K-FSR-P8: UI requested AMD RCAS sharpness'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0 -and
       $feed.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR P8 verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'FSR-P8 AMD RCAS stage applied: independent 0-1 sharpness control wired into FidelityFX dispatch.'
