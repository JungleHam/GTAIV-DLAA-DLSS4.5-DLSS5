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
$nr=Once $nr '    unsigned passes_ = 1;' @'
    unsigned passes_ = 1;
    unsigned nrStyle_ = 0, nrAutoMask_ = 1, nrUiCorrection_ = 0;
    float nrIntensity_ = 1.0f, nrLocalTone_ = 1.0f, nrLocalStructure_ = 1.0f, nrSkinStructure_ = 1.0f;
'@ 'NR state'
$nr=Once $nr '                 unsigned w, unsigned h, int flags, unsigned requestedPasses = 1) {' @'
                 unsigned w, unsigned h, int flags, unsigned requestedPasses = 1,
                 unsigned nrStyle = 0, float nrIntensity = 1.0f, float nrLocalTone = 1.0f,
                 float nrLocalStructure = 1.0f, float nrSkinStructure = 1.0f,
                 unsigned nrAutoMask = 1, unsigned nrUiCorrection = 0) {
'@ 'NR Prepare signature'
$nr=Once $nr '        if (requestedPasses > MaxPasses) requestedPasses = MaxPasses;' @'
        if (requestedPasses > MaxPasses) requestedPasses = MaxPasses;
        if (nrStyle > 2) nrStyle = 0;
        const auto clampNr=[](float v){return v<0.0f?0.0f:(v>2.0f?2.0f:v);};
        nrIntensity=clampNr(nrIntensity); nrLocalTone=clampNr(nrLocalTone);
        nrLocalStructure=clampNr(nrLocalStructure); nrSkinStructure=clampNr(nrSkinStructure);
        nrAutoMask=nrAutoMask?1u:0u; nrUiCorrection=nrUiCorrection?1u:0u;
'@ 'NR clamp'
$nr=Once $nr '            (device_ != device || w_ != w || h_ != h || flags_ != flags || passes_ != requestedPasses)) {' @'
            (device_ != device || w_ != w || h_ != h || flags_ != flags || passes_ != requestedPasses ||
             nrStyle_ != nrStyle || nrIntensity_ != nrIntensity || nrLocalTone_ != nrLocalTone ||
             nrLocalStructure_ != nrLocalStructure || nrSkinStructure_ != nrSkinStructure ||
             nrAutoMask_ != nrAutoMask || nrUiCorrection_ != nrUiCorrection)) {
'@ 'NR rebuild gate'
$nr=Once $nr '            return Ready() && device_ == device && w_ == w && h_ == h && flags_ == flags && passes_ == requestedPasses;' @'
            return Ready() && device_ == device && w_ == w && h_ == h && flags_ == flags && passes_ == requestedPasses &&
                nrStyle_ == nrStyle && nrIntensity_ == nrIntensity && nrLocalTone_ == nrLocalTone &&
                nrLocalStructure_ == nrLocalStructure && nrSkinStructure_ == nrSkinStructure &&
                nrAutoMask_ == nrAutoMask && nrUiCorrection_ == nrUiCorrection;
'@ 'NR ready gate'
$nr=Once $nr '        w_ = w; h_ = h; flags_ = flags; passes_ = requestedPasses;' @'
        w_ = w; h_ = h; flags_ = flags; passes_ = requestedPasses;
        nrStyle_=nrStyle; nrIntensity_=nrIntensity; nrLocalTone_=nrLocalTone;
        nrLocalStructure_=nrLocalStructure; nrSkinStructure_=nrSkinStructure;
        nrAutoMask_=nrAutoMask; nrUiCorrection_=nrUiCorrection;
'@ 'NR assign'
$nr=Once $nr '            m3k::CreateContract(pass_[i].params, w, h, flags);' @'
            m3k::CreateContract(pass_[i].params, w, h, flags);
            pass_[i].params->Set("DLSSNR.Style", nrStyle_);
            pass_[i].params->Set("DLSSNR.Intensity", nrIntensity_);
            pass_[i].params->Set("DLSSNR.LocalToneStrength", nrLocalTone_);
            pass_[i].params->Set("DLSSNR.LocalStructureStrength", nrLocalStructure_);
            pass_[i].params->Set("DLSSNR.SkinStructureStrength", nrSkinStructure_);
            pass_[i].params->Set("DLSSNR.UseAutoMask", nrAutoMask_);
            pass_[i].params->Set("DLSSNR.UICorrection", nrUiCorrection_);
'@ 'NR parameter override'

$vk=Once $vk 'static UINT g_m3kNrPasses = 1;' @'
static UINT g_m3kNrPasses = 1;
static UINT g_m3kNrStyle=0, g_m3kNrAutoMask=1, g_m3kNrUiCorrection=0;
static float g_m3kNrIntensity=1.0f, g_m3kNrLocalTone=1.0f, g_m3kNrLocalStructure=1.0f, g_m3kNrSkinStructure=1.0f;
static UINT g_m3kCustomScalePercent=77;
static bool g_m3kCustomScaleRejected=false;
'@ 'public state'

$prepareAt=$vk.IndexOf('static void M3kPrepareFrame()',[StringComparison]::Ordinal)
if($prepareAt -lt 0){throw 'M3kPrepareFrame marker missing'}
$floatReader=@'
static float M3kReadPublicFloat(const wchar_t *path,con