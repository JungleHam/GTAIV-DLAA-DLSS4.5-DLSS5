$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3I-G.bat from this branch." }

function Read-Normalized([string]$path) { return (Get-Content $path -Raw).Replace("`r`n", "`n") }
function Write-Normalized([string]$path, [string]$text) { Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8 }

$text = Read-Normalized $cpp

if (!$text.Contains('#include <tlhelp32.h>')) {
    $a = '#include <cmath>'
    $p = $text.IndexOf($a)
    if ($p -lt 0) { throw 'M3I-G include anchor missing: <cmath>' }
    $text = $text.Insert($p + $a.Length, "`n#include <tlhelp32.h>")
}
if (!$text.Contains('#include <vector>')) {
    $a = '#include <string>'
    $p = $text.IndexOf($a)
    if ($p -lt 0) { throw 'M3I-G include anchor missing: <string>' }
    $text = $text.Insert($p + $a.Length, "`n#include <vector>")
}

$func = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
$funcPos = $text.IndexOf($func)
if ($funcPos -lt 0) { throw 'M3I-G anchor missing: M2bBuildConstants' }

if (!$text.Contains('// M3I-G live GTA IV temporal camera transforms')) {
$helper = @'
// M3I-G live GTA IV temporal camera transforms.
// One-variable test on top of M3I-F: use GTA's real current/previous VIEW matrices
// to populate clipToPrevClip and prevClipToClip. Projection/MV/pacing remain unchanged.
struct M3gCameraSample
{
    uintptr_t address = 0;
    float view[16] = {};
    float viewInv[16] = {};
    int width = 0, height = 0;
    float fov = 0.0f, aspect = 0.0f, nearClip = 0.0f, farClip = 0.0f;
};

static HANDLE g_m3g_process = nullptr;
static uintptr_t g_m3g_viewport = 0;
static bool g_m3g_scanAttempted = false;
static bool g_m3g_havePrev = false;
static float g_m3g_prevView[16] = {};
static float g_m3g_prevViewInv[16] = {};
static unsigned long long g_m3g_evalCount = 0;

static bool M3gReadRemote(uintptr_t address, void *dst, size_t bytes)
{
    if (g_m3g_process == nullptr || address == 0 || dst == nullptr || bytes == 0) return false;
    SIZE_T got = 0;
    return ReadProcessMemory(g_m3g_process, reinterpret_cast<LPCVOID>(address), dst, bytes, &got) && got == bytes;
}

static bool M3gAttachGta()
{
    if (g_m3g_process != nullptr) return true;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return false;
    DWORD pid = 0;
    PROCESSENTRY32W pe = {}; pe.dwSize = sizeof(pe);
    if (Process32FirstW(snap, &pe)) {
        do { if (_wcsicmp(pe.szExeFile, L"GTAIV.exe") == 0) { pid = pe.th32ProcessID; break; } }
        while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    if (pid == 0) return false;
    g_m3g_process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (g_m3g_process == nullptr) return false;
    Log("[feed] M3I-G: attached GTAIV.exe pid=%lu", static_cast<unsigned long>(pid));
    return true;
}

static bool M3gFinite16(const float *m)
{
    float energy = 0.0f;
    for (int i = 0; i < 16; ++i) { if (!std::isfinite(m[i])) return false; energy += fabsf(m[i]); }
    return energy > 0.01f && energy < 10000000.0f;
}

static bool M3gReadCamera(uintptr_t base, M3gCameraSample &s)
{
    s = {}; s.address = base;
    if (!M3gReadRemote(base + 0x180, s.view, sizeof(s.view))) return false;
    if (!M3gReadRemote(base + 0x140, s.viewInv, sizeof(s.viewInv))) return false;
    if (!M3gReadRemote(base + 0x2B0, &s.width, sizeof(s.width))) return false;
    if (!M3gReadRemote(base + 0x2B4, &s.height, sizeof(s.height))) return false;
    if (!M3gReadRemote(base + 0x2B8, &s.fov, sizeof(s.fov))) return false;
    if (!M3gReadRemote(base + 0x2BC, &s.aspect, sizeof(s.aspect))) return false;
    if (!M3gReadRemote(base + 0x2C0, &s.nearClip, sizeof(s.nearClip))) return false;
    if (!M3gReadRemote(base + 0x2C4, &s.farClip, sizeof(s.farClip))) return false;
    if (s.width != static_cast<int>(g.width) || s.height != static_cast<int>(g.height)) return false;
    if (!(s.fov > 1.0f && s.fov < 179.0f && s.aspect > 0.25f && s.aspect < 5.0f)) return false;
    if (!(s.nearClip > 0.00001f && s.farClip > s.nearClip && s.farClip < 1000000.0f)) return false;
    return M3gFinite16(s.view) && M3gFinite16(s.viewInv);
}

static bool M3gWritable(DWORD protect)
{
    const DWORD p = protect & 0xFFu;
    return p == PAGE_READWRITE || p == PAGE_WRITECOPY || p == PAGE_EXECUTE_READWRITE || p == PAGE_EXECUTE_WRITECOPY;
}

static bool M3gFindViewport()
{
    if (g_m3g_viewport != 0) return true;
    if (g_m3g_scanAttempted) return false;
    g_m3g_scanAttempted = true;
    if (!M3gAttachGta() || g.width == 0 || g.height == 0) { g_m3g_scanAttempted = false; return false; }

    const uintptr_t maxAddress = 0xFFFFFFFFull;
    const size_t chunkSize = 1024 * 1024;
    float bestScore = 1.0e30f;
    uintptr_t best = 0;
    uintptr_t p = 0x10000;
    while (p < maxAddress)
    {
        MEMORY_BASIC_INFORMATION mbi = {};
        if (VirtualQueryEx(g_m3g_process, reinterpret_cast<LPCVOID>(p), &mbi, sizeof(mbi)) == 0) break;
        const uintptr_t rs = reinterpret_cast<uintptr_t>(mbi.BaseAddress);
        uintptr_t re = rs + mbi.RegionSize;
        if (re <= p) break;
        if (re > maxAddress) re = maxAddress;
        const bool eligible = mbi.State == MEM_COMMIT && (mbi.Protect & PAGE_GUARD) == 0 && M3gWritable(mbi.Protect);
        if (eligible)
        {
            for (uintptr_t cs = rs; cs < re; )
            {
                const size_t want = static_cast<size_t>((re - cs) > chunkSize ? chunkSize : (re - cs));
                if (want < 8) break;
                std::vector<unsigned char> buf(want);
                SIZE_T got = 0;
                if (ReadProcessMemory(g_m3g_process, reinterpret_cast<LPCVOID>(cs), buf.data(), want, &got) && got >= 8)
                {
                    const size_t n = static_cast<size_t>(got);
                    for (size_t i = 0; i + 8 <= n; i += 4)
                    {
                        int w = 0, h = 0;
                        memcpy(&w, buf.data() + i, 4); if (w != static_cast<int>(g.width)) continue;
                        memcpy(&h, buf.data() + i + 4, 4); if (h != static_cast<int>(g.height)) continue;
                        const uintptr_t wa = cs + i; if (wa < 0x2B0) continue;
                        M3gCameraSample s = {};
                        const uintptr_t candidate = wa - 0x2B0;
                        if (!M3gReadCamera(candidate, s)) continue;
                        const float targetAspect = static_cast<float>(g.width) / static_cast<float>(g.height);
                        const float score = fabsf(s.aspect - targetAspect) * 1000.0f +
                                            fabsf(s.nearClip - 0.05f) * 1000.0f +
                                            fabsf(s.farClip - 1500.0f) * 0.05f +
                                            fabsf(s.fov - 45.0f) * 0.25f;
                        if (score < bestScore) { bestScore = score; best = candidate; }
                    }
                }
                cs += want;
            }
        }
        p = re;
    }
    if (best == 0) { Log("[feed] M3I-G: main viewport not found"); return false; }
    g_m3g_viewport = best;
    Log("[feed] M3I-G: viewport FOUND address=0x%llX score=%.6f", static_cast<unsigned long long>(best), bestScore);
    return true;
}

static void M3gMul(const float *a, const float *b, float *out)
{
    float t[16] = {};
    for (int r = 0; r < 4; ++r)
        for (int c = 0; c < 4; ++c) {
            float s = 0.0f;
            for (int k = 0; k < 4; ++k) s += a[r * 4 + k] * b[k * 4 + c];
            t[r * 4 + c] = s;
        }
    memcpy(out, t, sizeof(t));
}

static float M3gMaxIdentityDelta(const float *m)
{
    float e = 0.0f;
    for (int r = 0; r < 4; ++r)
        for (int c = 0; c < 4; ++c) {
            const float want = (r == c) ? 1.0f : 0.0f;
            e = (std::max)(e, fabsf(m[r * 4 + c] - want));
        }
    return e;
}

static void M3gApplyTemporalCamera(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)
{
    ++g_m3g_evalCount;
    if (!M3gFindViewport()) { g_m3g_havePrev = false; return; }
    M3gCameraSample cur = {};
    if (!M3gReadCamera(g_m3g_viewport, cur)) { g_m3g_havePrev = false; return; }

    if (reset || !g_m3g_havePrev)
    {
        memcpy(g_m3g_prevView, cur.view, sizeof(g_m3g_prevView));
        memcpy(g_m3g_prevViewInv, cur.viewInv, sizeof(g_m3g_prevViewInv));
        g_m3g_havePrev = true;
        Log("[feed] M3I-G: temporal camera SEEDED reset=%d", reset ? 1 : 0);
        return;
    }

    const float *P = &op->cameraViewToClip[0][0];
    const float *invP = &op->clipToCameraView[0][0];
    float t0[16], t1[16], c2p[16], p2c[16];

    // GTA IV uses row-vector D3D composition: clip = world * VIEW * PROJ.
    // Current clip -> previous clip = inv(Pcur) * inv(Vcur) * Vprev * Pprev.
    M3gMul(invP, cur.viewInv, t0);
    M3gMul(t0, g_m3g_prevView, t1);
    M3gMul(t1, P, c2p);

    // Previous clip -> current clip = inv(Pprev) * inv(Vprev) * Vcur * Pcur.
    M3gMul(invP, g_m3g_prevViewInv, t0);
    M3gMul(t0, cur.view, t1);
    M3gMul(t1, P, p2c);

    if (M3gFinite16(c2p) && M3gFinite16(p2c))
    {
        memcpy(op->clipToPrevClip, c2p, sizeof(c2p));
        memcpy(op->prevClipToClip, p2c, sizeof(p2c));
        if (g_m3g_evalCount <= 4 || (g_m3g_evalCount % 120ull) == 0)
            Log("[feed] M3I-G: LIVE temporal transforms eval=%llu c2pDelta=%.9g p2cDelta=%.9g",
                g_m3g_evalCount, M3gMaxIdentityDelta(c2p), M3gMaxIdentityDelta(p2c));
    }

    memcpy(g_m3g_prevView, cur.view, sizeof(g_m3g_prevView));
    memcpy(g_m3g_prevViewInv, cur.viewInv, sizeof(g_m3g_prevViewInv));
}
'@
    $text = $text.Insert($funcPos, $helper + "`n")
}

$anchor = @'
    M2bIdentity(op->clipToLensClip);
    M2bIdentity(op->clipToPrevClip);
    M2bIdentity(op->prevClipToClip);
'@
$replacement = @'
    M2bIdentity(op->clipToLensClip);
    M2bIdentity(op->clipToPrevClip);
    M2bIdentity(op->prevClipToClip);
    M3gApplyTemporalCamera(op, reset); // M3I-G: live GTA IV current/previous camera transform
'@

if (!$text.Contains('M3gApplyTemporalCamera(op, reset); // M3I-G: live GTA IV current/previous camera transform')) {
    $p = $text.IndexOf($anchor, $funcPos)
    if ($p -lt 0) { throw 'M3I-G temporal identity anchor not found' }
    $text = $text.Remove($p, $anchor.Length).Insert($p, $replacement)
}

Write-Normalized $cpp $text
Write-Host 'Applied M3I-G: live GTA IV current/previous VIEW temporal clip transforms.'
Write-Host 'M3I-F projection, MV scale/data, cameraMotionIncluded, pacing and transport are unchanged.'
