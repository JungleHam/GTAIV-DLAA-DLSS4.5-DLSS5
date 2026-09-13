$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'
$inc = Join-Path $m2b 'feeder-src\src\m3b2b-feed.inc'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3H.bat first." }
if (!(Test-Path $inc)) { throw "Missing $inc. Run BUILD-M3H.bat first." }

function Read-Normalized([string]$path) {
    return (Get-Content $path -Raw).Replace("`r`n", "`n")
}
function Write-Normalized([string]$path, [string]$text) {
    Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8
}

$cppText = Read-Normalized $cpp
if (!$cppText.Contains('[feed] M3I-A: CREATE contract')) {
    $createAnchor = @'
static NVSDK_NGX_Result SafeCreateDLFG(NVSDK_NGX_DLSSG_Create_Params *cp, DWORD *code)
{
    *code = 0;
'@
    $createReplacement = @'
static NVSDK_NGX_Result SafeCreateDLFG(NVSDK_NGX_DLSSG_Create_Params *cp, DWORD *code)
{
    *code = 0;
    if (cp != nullptr)
    {
        Log("[feed] M3I-A: CREATE contract Width=%u Height=%u RenderWidth=%u RenderHeight=%u NativeFormat=%u DRS=%d g=%ux%u",
            cp->Width, cp->Height, cp->RenderWidth, cp->RenderHeight,
            cp->NativeBackbufferFormat, cp->DynamicResolutionScaling ? 1 : 0,
            g.width, g.height);
    }
'@
    if (!$cppText.Contains($createAnchor)) { throw 'M3I-A anchor not found: SafeCreateDLFG prologue' }
    $cppText = $cppText.Replace($createAnchor, $createReplacement)
    Write-Normalized $cpp $cppText
}

$incText = Read-Normalized $inc
if (!$incText.Contains('// M3I-A resolution/subrect audit')) {
    $evalAnchor = 'static M3b2bEvalResult M3b2bEvaluate(UINT64 frame, bool reset)'
    $pos = $incText.IndexOf($evalAnchor)
    if ($pos -lt 0) { throw 'M3I-A anchor not found: M3b2bEvaluate' }

    $helper = @'
// M3I-A resolution/subrect audit.
// Diagnostic only: no feature-11 inputs are intentionally changed.
static bool g_m3i_a_logged_reset = false;
static bool g_m3i_a_logged_live = false;

static void M3iAuditResource(const char *name, ID3D12Resource *resource)
{
    if (resource == nullptr)
    {
        Log("[feed] M3I-A: RESOURCE %s = NULL", name ? name : "?");
        return;
    }
    const D3D12_RESOURCE_DESC d = resource->GetDesc();
    Log("[feed] M3I-A: RESOURCE %s width=%llu height=%u format=%u dimension=%u mips=%u array=%u samples=%u quality=%u layout=%u flags=0x%X alignment=%llu",
        name ? name : "?", static_cast<unsigned long long>(d.Width), d.Height,
        static_cast<unsigned>(d.Format), static_cast<unsigned>(d.Dimension),
        static_cast<unsigned>(d.MipLevels), static_cast<unsigned>(d.DepthOrArraySize),
        d.SampleDesc.Count, d.SampleDesc.Quality, static_cast<unsigned>(d.Layout),
        static_cast<unsigned>(d.Flags), static_cast<unsigned long long>(d.Alignment));
}

static void M3iAuditRect(const char *name,
                         const NVSDK_NGX_Coordinates &base,
                         const NVSDK_NGX_Dimensions &size)
{
    Log("[feed] M3I-A: SUBRECT %s base=%u,%u size=%ux%u",
        name ? name : "?", base.X, base.Y, size.Width, size.Height);
}

static void M3iAuditEvalContract(UINT64 frame, bool reset,
                                 const NVSDK_NGX_DLSSG_Opt_Eval_Params &op)
{
    if (reset)
    {
        if (g_m3i_a_logged_reset) return;
        g_m3i_a_logged_reset = true;
    }
    else
    {
        if (g_m3i_a_logged_live) return;
        g_m3i_a_logged_live = true;
    }

    Log("[feed] M3I-A: EVAL contract frame=%llu reset=%d g=%ux%u work_resolution=%d%% work_upscale=%d work_sharpness=%.3f",
        static_cast<unsigned long long>(frame), reset ? 1 : 0,
        g.width, g.height, g_cfg.work_resolution, g_cfg.work_upscale, g_cfg.work_sharpness);
    Log("[feed] M3I-A: EVAL meta multiFrame=%u/%u mvecScale=(%.9f,%.9f) jitter=(%.6f,%.6f) cameraMotionIncluded=%d motionVectorsDilated=%d cameraFOV=%.6f near=%.6f far=%.3f aspect=%.6f",
        op.multiFrameIndex, op.multiFrameCount,
        op.mvecScale[0], op.mvecScale[1], op.jitterOffset[0], op.jitterOffset[1],
        op.cameraMotionIncluded ? 1 : 0, op.motionVectorsDilated ? 1 : 0,
        op.cameraFOV, op.cameraNear, op.cameraFar, op.cameraAspectRatio);

    M3iAuditResource("SLOT_COLOR", g.tex12[SLOT_COLOR]);
    M3iAuditResource("SLOT_OUTPUT/backbuffer", g.tex12[SLOT_OUTPUT]);
    M3iAuditResource("SLOT_DEPTH", g.tex12[SLOT_DEPTH]);
    M3iAuditResource("SLOT_MV", g.tex12[SLOT_MV]);
    M3iAuditResource("DLSSG_outputInterp", g.m3b1a_tex12);

    M3iAuditRect("mvecs", op.mvecsSubrectBase, op.mvecsSubrectSize);
    M3iAuditRect("depth", op.depthSubrectBase, op.depthSubrectSize);
    M3iAuditRect("hudLess", op.hudLessSubrectBase, op.hudLessSubrectSize);
    M3iAuditRect("ui", op.uiSubrectBase, op.uiSubrectSize);
    M3iAuditRect("uiAlpha", op.uiAlphaSubrectBase, op.uiAlphaSubrectSize);
    M3iAuditRect("bidirectionalDistField", op.bidirectionalDistFieldSubrectBase, op.bidirectionalDistFieldSubrectSize);
    M3iAuditRect("backbuffer", op.backbufferSubrectBase, op.backbufferSubrectSize);
    M3iAuditRect("outputInterp", op.outputInterpSubrectBase, op.outputInterpSubrectSize);
    M3iAuditRect("outputReal", op.outputRealSubrectBase, op.outputRealSubrectSize);
}

'@
    $incText = $incText.Insert($pos, $helper)
}

if (!$incText.Contains('M3iAuditEvalContract(frame, reset, op);')) {
    $callAnchor = @'
    NVSDK_NGX_DLSSG_Opt_Eval_Params op = {};
    M2bBuildConstants(&op, reset);

    DWORD code = 0;
'@
    $callReplacement = @'
    NVSDK_NGX_DLSSG_Opt_Eval_Params op = {};
    M2bBuildConstants(&op, reset);
    M3iAuditEvalContract(frame, reset, op);

    DWORD code = 0;
'@
    if (!$incText.Contains($callAnchor)) { throw 'M3I-A anchor not found: M3b2bEvaluate constants/evaluate site' }
    $incText = $incText.Replace($callAnchor, $callReplacement)
}

Write-Normalized $inc $incText
Write-Host 'Applied M3I-A zero-behaviour-change resolution/subrect audit.'
