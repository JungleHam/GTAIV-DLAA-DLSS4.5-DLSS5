[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'
$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
if(-not(Test-Path -LiteralPath $vkPath)){throw "Missing generated source: $vkPath"}
if(-not(Test-Path -LiteralPath $FeederSource)){throw "Missing feeder source: $FeederSource"}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if($count-ne 1){throw "P9C.4 $Label expected once, found $count"}
    return $Text.Replace($Old,$New)
}

$vk=Once $vk 'static UINT g_m3kJitterCompMode=1; // hardware-confirmed GTA IV compensation: +1/+1' 'static UINT g_m3kJitterCompMode=0; // 0=+X/+Y, 1=-X/-Y, 2=+X/-Y, 3=-X/+Y' 'jitter compensation state'
$vk=Once $vk 'static float M3kJitterCompX(){return 1.0f;}' 'static float M3kJitterCompX(){return (g_m3kJitterCompMode==1u||g_m3kJitterCompMode==3u)?-1.0f:+1.0f;}' 'jitter compensation X'
$vk=Once $vk 'static float M3kJitterCompY(){return 1.0f;}' 'static float M3kJitterCompY(){return (g_m3kJitterCompMode==1u||g_m3kJitterCompMode==2u)?-1.0f:+1.0f;}' 'jitter compensation Y'

$oldPoll='        g_m3kJitterCompMode=1u; // +1/+1 is the confirmed stable compensation; ignore old calibration state'
$newPoll=@'
        const UINT rawJitterComp=GetPrivateProfileIntW(L"M3K",L"NvidiaJitterCompMode",0,path);
        g_m3kJitterCompMode=rawJitterComp<=3u?rawJitterComp:0u;
'@
$vk=Once $vk $oldPoll $newPoll 'jitter compensation INI poll'

$helpers=@'
static UINT M3kNvidiaJitterCompModeRequested(){return g_m3kJitterCompMode;}
static const char *M3kNvidiaJitterCompModeName(UINT mode)
{
    switch(mode){
    case 1u:return "-X / -Y";
    case 2u:return "+X / -Y";
    case 3u:return "-X / +Y";
    default:return "+X / +Y";
    }
}
static void M3kRequestNvidiaJitterCompModeLive(UINT mode)
{
    if(mode>3u)mode=0u;
    if(mode==g_m3kJitterCompMode)return;
    g_m3kJitterCompMode=mode;
    M3kWritePublicUInt(L"NvidiaJitterCompMode",mode);
#if defined(VK_VERSION_1_0)
    g_m3kSrNeedsReset=true;
#endif
    g_m3k.ResetHistory();
    Log("M3K-P9C4: NVIDIA jitter compensation changed live -> %s (mode=%u); full raster jitter retained",
        M3kNvidiaJitterCompModeName(mode),mode);
}

'@
$prepare='static void M3kPrepareFrame()'
$at=$vk.IndexOf($prepare,[StringComparison]::Ordinal)
if($at-lt 0){throw 'P9C.4 M3kPrepareFrame anchor missing'}
$vk=$vk.Substring(0,$at)+$helpers+$vk.Substring($at)

$uiOld='            ImGui::TextDisabled("NGX compensation: +1/+1 (GTA IV calibrated)");'
$uiNew=@'
            int jitterCompChoice=static_cast<int>(M3kNvidiaJitterCompModeRequested());
            const char *jitterCompItems="+X / +Y\0-X / -Y\0+X / -Y\0-X / +Y\0\0";
            if(ImGui::Combo("NVIDIA Jitter Compensation##M3KJitterComp",&jitterCompChoice,jitterCompItems))
                M3kRequestNvidiaJitterCompModeLive(static_cast<UINT>(jitterCompChoice));
            ImGui::TextDisabled("Full raster jitter stays ON. This changes only the X/Y sign reported to NVIDIA NGX.");
'@
$feed=Once $feed $uiOld $uiNew 'NVIDIA jitter compensation UI'

$diagOld='ImGui::Text("Jitter: mode=%s effective=%u phases NGX=(+1.00,+1.00)",M3kJitterModeRequested()==0?"Auto":"Manual",M3kJitterEffectivePhases());'
$diagNew='ImGui::Text("Jitter: mode=%s effective=%u phases NVIDIA=%s",M3kJitterModeRequested()==0?"Auto":"Manual",M3kJitterEffectivePhases(),M3kNvidiaJitterCompModeName(M3kNvidiaJitterCompModeRequested()));'
if($feed.Contains($diagOld)){$feed=$feed.Replace($diagOld,$diagNew)}

foreach($marker in @(
    'M3K-P9C4: NVIDIA jitter compensation changed live -> %s',
    'NvidiaJitterCompMode',
    'Full raster jitter stays ON.',
    'NVIDIA Jitter Compensation##M3KJitterComp'
)){
    if(($vk+$feed).IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "P9C.4 verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'P9C.4 applied: full raster jitter retained; NVIDIA NGX X/Y sign can be calibrated live.'
