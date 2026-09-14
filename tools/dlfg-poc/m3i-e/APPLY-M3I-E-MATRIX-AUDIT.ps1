$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3I-E.bat from this branch." }

function Read-Normalized([string]$path) {
    return (Get-Content $path -Raw).Replace("`r`n", "`n")
}
function Write-Normalized([string]$path, [string]$text) {
    Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8
}

$text = Read-Normalized $cpp

# The clean M3I-D source intentionally contains no M3I-C memory scanner. M3I-E adds a
# small audit-only reader with its own process discovery and one-time viewport scan.
if (!$text.Contains('#include <tlhelp32.h>')) {
    $incAnchor = '#include <cmath>'
    $incPos = $text.IndexOf($incAnchor)
    if ($incPos -lt 0) { throw 'M3I-E include anchor not found: <cmath>' }
    $text = $text.Insert($incPos + $incAnchor.Length, "`n#include <tlhelp32.h>")
}
if (!$text.Contains('#include <vector>')) {
    $incAnchor = '#include <string>'
    $incPos = $text.IndexOf($incAnchor)
    if ($incPos -lt 0) { throw 'M3I-E include anchor not found: <string>' }
    $text = $text.Insert($incPos + $incAnchor.Length, "`n#include <vector>")
}

if (!$text.Contains('// M3I-E live GTA IV camera matrix audit')) {
    $anchor = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
    $pos = $text.IndexOf($anchor)
    if ($pos -lt 0) { throw 'M3I-E anchor not found: M2bBuildConstants' }

    $helper = @'
// M3I-E live GTA IV camera matrix audit.
// Diagnostic only: reads the 32-bit GTAIV.exe process and never writes to it.
// FusionFix documents grcViewport as:
//   +0x040 camera, +0x100 worldViewProj, +0x140 viewInverse,
//   +0x180 view, +0x1C0 projection, +0x2B0 width/height/FOV/aspect/near/far.
// We locate the main 2560x1440-style viewport once, then sample its matrices while
// the player pans the camera. No DLSS-G inputs are changed by this audit.
struct M3eViewportSnapshot
{
    uintptr_t address = 0;
    float world[16] = {};
    float camera[16] = {};
    float worldViewProj[16] = {};
    float viewInverse[16] = {};
    float view[16] = {};
    float projection[16] = {};
    int width = 0;
    int height = 0;
    float fov = 0.0f;
    float aspect = 0.0f;
    float nearClip = 0.0f;
    float farClip = 0.0f;
};

static HANDLE g_m3e_process = nullptr;
static DWORD g_m3e_pid = 0;
static uintptr_t g_m3e_viewport = 0;
static bool g_m3e_scanAttempted = false;
static unsigned long long g_m3e_tick = 0;
static float g_m3e_lastView[16] = {};
static bool g_m3e_haveLastView = false;

static bool M3eReadRemote(uintptr_t address, void *dst, size_t bytes)
{
    if (g_m3e_process == nullptr || address == 0 || dst == nullptr || bytes == 0) return false;
    SIZE_T got = 0;
    return ReadProcessMemory(g_m3e_process, reinterpret_cast<LPCVOID>(address), dst, bytes, &got) && got == bytes;
}

static bool M3eAttachGta()
{
    if (g_m3e_process != nullptr) return true;

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return false;

    DWORD pid = 0;
    PROCESSENTRY32W pe = {};
    pe.dwSize = sizeof(pe);
    if (Process32FirstW(snapshot, &pe))
    {
        do
        {
            if (_wcsicmp(pe.szExeFile, L"GTAIV.exe") == 0)
            {
                pid = pe.th32ProcessID;
                break;
            }
        } while (Process32NextW(snapshot, &pe));
    }
    CloseHandle(snapshot);
    if (pid == 0) return false;

    HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (process == nullptr) return false;

    g_m3e_process = process;
    g_m3e_pid = pid;
    Log("[feed] M3I-E: attached GTAIV.exe pid=%lu", static_cast<unsigned long>(pid));
    return true;
}

static bool M3eFiniteMatrix(const float *m)
{
    float energy = 0.0f;
    for (int i = 0; i < 16; ++i)
    {
        if (!std::isfinite(m[i])) return false;
        energy += fabsf(m[i]);
    }
    return energy > 0.01f && energy < 10000000.0f;
}

static bool M3eReadViewport(uintptr_t address, M3eViewportSnapshot &v)
{
    if (address == 0) return false;
    v = {};
    v.address = address;

    if (!M3eReadRemote(address + 0x080, v.world, sizeof(v.world))) return false;
    if (!M3eReadRemote(address + 0x040, v.camera, sizeof(v.camera))) return false;
    if (!M3eReadRemote(address + 0x100, v.worldViewProj, sizeof(v.worldViewProj))) return false;
    if (!M3eReadRemote(address + 0x140, v.viewInverse, sizeof(v.viewInverse))) return false;
    if (!M3eReadRemote(address + 0x180, v.view, sizeof(v.view))) return false;
    if (!M3eReadRemote(address + 0x1C0, v.projection, sizeof(v.projection))) return false;
    if (!M3eReadRemote(address + 0x2B0, &v.width, sizeof(v.width))) return false;
    if (!M3eReadRemote(address + 0x2B4, &v.height, sizeof(v.height))) return false;
    if (!M3eReadRemote(address + 0x2B8, &v.fov, sizeof(v.fov))) return false;
    if (!M3eReadRemote(address + 0x2BC, &v.aspect, sizeof(v.aspect))) return false;
    if (!M3eReadRemote(address + 0x2C0, &v.nearClip, sizeof(v.nearClip))) return false;
    if (!M3eReadRemote(address + 0x2C4, &v.farClip, sizeof(v.farClip))) return false;

    if (g.width == 0 || g.height == 0) return false;
    if (v.width != static_cast<int>(g.width) || v.height != static_cast<int>(g.height)) return false;
    if (!(v.fov > 1.0f && v.fov < 179.0f)) return false;
    if (!(v.aspect > 0.25f && v.aspect < 5.0f)) return false;
    if (!(v.nearClip > 0.00001f && v.nearClip < 100.0f)) return false;
    if (!(v.farClip > v.nearClip && v.farClip < 1000000.0f)) return false;
    if (!M3eFiniteMatrix(v.view) || !M3eFiniteMatrix(v.viewInverse) ||
        !M3eFiniteMatrix(v.projection) || !M3eFiniteMatrix(v.worldViewProj)) return false;
    return true;
}

static bool M3eWritableProtect(DWORD protect)
{
    const DWORD p = protect & 0xFFu;
    return p == PAGE_READWRITE || p == PAGE_WRITECOPY ||
           p == PAGE_EXECUTE_READWRITE || p == PAGE_EXECUTE_WRITECOPY;
}

static float M3eCandidateScore(const M3eViewportSnapshot &v)
{
    const float targetAspect = static_cast<float>(g.width) / static_cast<float>(g.height);
    // The hardware audit established the main scene family as ~45 deg, 16:9,
    // near=0.05, far=1500. Score rather than hard-require FOV so this still logs
    // something useful if the user is a slider-step away from exactly 45.
    return fabsf(v.aspect - targetAspect) * 1000.0f +
           fabsf(v.nearClip - 0.05f) * 1000.0f +
           fabsf(v.farClip - 1500.0f) * 0.05f +
           fabsf(v.fov - 45.0f) * 0.25f;
}

static bool M3eFindMainViewport()
{
    if (g_m3e_viewport != 0) return true;
    if (g_m3e_scanAttempted) return false;
    g_m3e_scanAttempted = true;

    if (!M3eAttachGta() || g.width == 0 || g.height == 0)
    {
        Log("[feed] M3I-E: viewport scan deferred/failed: GTAIV.exe or render size unavailable");
        g_m3e_scanAttempted = false;
        return false;
    }

    const uintptr_t maxAddress = 0xFFFFFFFFull;
    const size_t chunkSize = 1024 * 1024;
    uintptr_t p = 0x10000;
    size_t regions = 0, bytesRead = 0, resolutionHits = 0, validCandidates = 0;
    float bestScore = 1.0e30f;
    uintptr_t bestAddress = 0;
    M3eViewportSnapshot best = {};

    while (p < maxAddress)
    {
        MEMORY_BASIC_INFORMATION mbi = {};
        if (VirtualQueryEx(g_m3e_process, reinterpret_cast<LPCVOID>(p), &mbi, sizeof(mbi)) == 0) break;

        const uintptr_t regionStart = reinterpret_cast<uintptr_t>(mbi.BaseAddress);
        uintptr_t regionEnd = regionStart + mbi.RegionSize;
        if (regionEnd <= p) break;
        if (regionEnd > maxAddress) regionEnd = maxAddress;

        const DWORD prot = mbi.Protect & 0xFFu;
        const bool eligible = mbi.State == MEM_COMMIT && prot != PAGE_NOACCESS &&
                              (mbi.Protect & PAGE_GUARD) == 0 && M3eWritableProtect(mbi.Protect);
        if (eligible)
        {
            ++regions;
            for (uintptr_t chunkStart = regionStart; chunkStart < regionEnd; )
            {
                const size_t want = static_cast<size_t>((regionEnd - chunkStart) > chunkSize ? chunkSize : (regionEnd - chunkStart));
                if (want < 8) break;

                std::vector<unsigned char> buffer(want);
                SIZE_T got = 0;
                if (ReadProcessMemory(g_m3e_process, reinterpret_cast<LPCVOID>(chunkStart), buffer.data(), want, &got) && got >= 8)
                {
                    bytesRead += static_cast<size_t>(got);
                    const size_t n = static_cast<size_t>(got);
                    for (size_t i = 0; i + 8 <= n; i += 4)
                    {
                        int w = 0, h = 0;
                        memcpy(&w, buffer.data() + i, sizeof(w));
                        if (w != static_cast<int>(g.width)) continue;
                        memcpy(&h, buffer.data() + i + 4, sizeof(h));
                        if (h != static_cast<int>(g.height)) continue;
                        ++resolutionHits;

                        const uintptr_t widthAddress = chunkStart + i;
                        if (widthAddress < 0x2B0) continue;
                        const uintptr_t candidateAddress = widthAddress - 0x2B0;
                        M3eViewportSnapshot candidate = {};
                        if (!M3eReadViewport(candidateAddress, candidate)) continue;
                        ++validCandidates;

                        const float targetAspect = static_cast<float>(g.width) / static_cast<float>(g.height);
                        if (fabsf(candidate.aspect - targetAspect) > 0.05f) continue;
                        const float score = M3eCandidateScore(candidate);
                        Log("[feed] M3I-E: CANDIDATE address=0x%llX score=%.6f size=%dx%d fov=%.6f aspect=%.9f near=%.6f far=%.3f",
                            static_cast<unsigned long long>(candidateAddress), score,
                            candidate.width, candidate.height, candidate.fov, candidate.aspect,
                            candidate.nearClip, candidate.farClip);
                        if (score < bestScore)
                        {
                            bestScore = score;
                            bestAddress = candidateAddress;
                            best = candidate;
                        }
                    }
                }
                chunkStart += want;
            }
        }
        p = regionEnd;
    }

    Log("[feed] M3I-E: scan complete regions=%llu bytes=%llu resolutionHits=%llu validCandidates=%llu",
        static_cast<unsigned long long>(regions), static_cast<unsigned long long>(bytesRead),
        static_cast<unsigned long long>(resolutionHits), static_cast<unsigned long long>(validCandidates));

    if (bestAddress == 0)
    {
        Log("[feed] M3I-E: no usable main viewport candidate found");
        return false;
    }

    g_m3e_viewport = bestAddress;
    Log("[feed] M3I-E: SELECTED address=0x%llX score=%.6f fov=%.6f aspect=%.9f near=%.6f far=%.3f",
        static_cast<unsigned long long>(bestAddress), bestScore, best.fov, best.aspect,
        best.nearClip, best.farClip);
    return true;
}

static void M3eMatMul(const float *a, const float *b, float *out)
{
    for (int r = 0; r < 4; ++r)
        for (int c = 0; c < 4; ++c)
        {
            float s = 0.0f;
            for (int k = 0; k < 4; ++k) s += a[r * 4 + k] * b[k * 4 + c];
            out[r * 4 + c] = s;
        }
}

static float M3eMaxIdentityError(const float *m)
{
    float e = 0.0f;
    for (int r = 0; r < 4; ++r)
        for (int c = 0; c < 4; ++c)
        {
            const float want = (r == c) ? 1.0f : 0.0f;
            e = (std::max)(e, fabsf(m[r * 4 + c] - want));
        }
    return e;
}

static float M3eMaxDiff(const float *a, const float *b)
{
    float e = 0.0f;
    for (int i = 0; i < 16; ++i) e = (std::max)(e, fabsf(a[i] - b[i]));
    return e;
}

static void M3eLogMatrix(const char *name, unsigned long long sample, const float *m)
{
    Log("[feed] M3I-E: MAT sample=%llu %s=[%.9g,%.9g,%.9g,%.9g; %.9g,%.9g,%.9g,%.9g; %.9g,%.9g,%.9g,%.9g; %.9g,%.9g,%.9g,%.9g]",
        sample, name,
        m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7],
        m[8], m[9], m[10], m[11], m[12], m[13], m[14], m[15]);
}

static void M3eMatrixAuditTick()
{
    ++g_m3e_tick;
    if (!M3eFindMainViewport()) return;

    // About two samples per second at a 60-fps real-frame cap. This is deliberately
    // sparse so the audit cannot become a meaningful runtime load.
    if (g_m3e_tick != 1 && (g_m3e_tick % 30ull) != 0) return;

    M3eViewportSnapshot v = {};
    if (!M3eReadViewport(g_m3e_viewport, v))
    {
        Log("[feed] M3I-E: selected viewport became unreadable address=0x%llX",
            static_cast<unsigned long long>(g_m3e_viewport));
        g_m3e_viewport = 0;
        g_m3e_scanAttempted = false;
        return;
    }

    float vvInv[16] = {}, invVv[16] = {}, viewProj[16] = {}, projView[16] = {};
    float worldView[16] = {}, worldViewProj[16] = {};
    M3eMatMul(v.view, v.viewInverse, vvInv);
    M3eMatMul(v.viewInverse, v.view, invVv);
    M3eMatMul(v.view, v.projection, viewProj);
    M3eMatMul(v.projection, v.view, projView);
    M3eMatMul(v.world, v.view, worldView);
    M3eMatMul(worldView, v.projection, worldViewProj);

    const float deltaView = g_m3e_haveLastView ? M3eMaxDiff(v.view, g_m3e_lastView) : 0.0f;
    memcpy(g_m3e_lastView, v.view, sizeof(g_m3e_lastView));
    g_m3e_haveLastView = true;

    Log("[feed] M3I-E: SAMPLE tick=%llu address=0x%llX fov=%.6f aspect=%.9f near=%.6f far=%.3f viewDelta=%.9g invErr(V*Vi)=%.9g invErr(Vi*V)=%.9g wvpErr(W*V*P)=%.9g wvpErr(V*P)=%.9g wvpErr(P*V)=%.9g",
        g_m3e_tick, static_cast<unsigned long long>(v.address),
        v.fov, v.aspect, v.nearClip, v.farClip, deltaView,
        M3eMaxIdentityError(vvInv), M3eMaxIdentityError(invVv),
        M3eMaxDiff(v.worldViewProj, worldViewProj),
        M3eMaxDiff(v.worldViewProj, viewProj), M3eMaxDiff(v.worldViewProj, projView));

    M3eLogMatrix("WORLD", g_m3e_tick, v.world);
    M3eLogMatrix("CAMERA", g_m3e_tick, v.camera);
    M3eLogMatrix("WVP", g_m3e_tick, v.worldViewProj);
    M3eLogMatrix("VIEWINV", g_m3e_tick, v.viewInverse);
    M3eLogMatrix("VIEW", g_m3e_tick, v.view);
    M3eLogMatrix("PROJ", g_m3e_tick, v.projection);
}

'@
    $text = $text.Insert($pos, $helper)
}

# Call the audit inside the DLSS-G constants path, but do not modify any constants.
$func = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
$funcPos = $text.IndexOf($func)
if ($funcPos -lt 0) { throw 'M3I-E call anchor not found: M2bBuildConstants' }
if (!$text.Contains('M3eMatrixAuditTick();')) {
    $resetStmt = '    *op = {};'
    $resetPos = $text.IndexOf($resetStmt, $funcPos)
    if ($resetPos -lt 0) { throw 'M3I-E call anchor not found: *op = {};' }
    $insertPos = $resetPos + $resetStmt.Length
    $text = $text.Insert($insertPos, "`n    M3eMatrixAuditTick();")
}

Write-Normalized $cpp $text
Write-Host 'Applied M3I-E live GTA IV camera-matrix audit (diagnostic only).'
