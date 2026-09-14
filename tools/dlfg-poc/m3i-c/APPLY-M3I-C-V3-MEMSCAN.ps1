$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3I-C.bat from this branch." }

function Read-Normalized([string]$path) {
    return (Get-Content $path -Raw).Replace("`r`n", "`n")
}
function Write-Normalized([string]$path, [string]$text) {
    Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8
}

$text = Read-Normalized $cpp

if (!$text.Contains('// M3I-C v3 direct viewport-structure memory scan')) {
    $anchor = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
    $pos = $text.IndexOf($anchor)
    if ($pos -lt 0) { throw 'M3I-C v3 anchor not found: M2bBuildConstants' }

    $helper = @'
// M3I-C v3 direct viewport-structure memory scan.
// Diagnostic only. V1/V2 proved GTAIV.exe is readable but the documented signature
// does not identify the live viewport in this executable. V3 therefore searches
// committed process memory for the actual grcViewport layout itself, using the known
// 0x2B0 width / 0x2B4 height / 0x2B8 FOV / 0x2BC aspect / 0x2C0 near / 0x2C4 far
// field layout documented by FusionFix. It never writes to GTA IV or changes DLSS-G.
struct M3iV3Candidate
{
    uintptr_t address = 0;
    M3iViewportValues last = {};
    bool haveLast = false;
};

static std::vector<M3iV3Candidate> g_m3i_v3_candidates;
static HANDLE g_m3i_v3_process = nullptr;
static DWORD g_m3i_v3_pid = 0;
static ULONGLONG g_m3i_v3_nextScanMs = 0;
static ULONGLONG g_m3i_v3_nextPollMs = 0;
static unsigned g_m3i_v3_scanAttempt = 0;

static bool M3iV3AttachProcess()
{
    if (g_m3i_v3_process != nullptr) return true;

    DWORD pid = 0;
    HANDLE ps = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (ps != INVALID_HANDLE_VALUE)
    {
        PROCESSENTRY32W pe = {};
        pe.dwSize = sizeof(pe);
        if (Process32FirstW(ps, &pe))
        {
            do
            {
                if (_wcsicmp(pe.szExeFile, L"GTAIV.exe") == 0)
                {
                    pid = pe.th32ProcessID;
                    break;
                }
            } while (Process32NextW(ps, &pe));
        }
        CloseHandle(ps);
    }
    if (pid == 0) return false;

    HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (process == nullptr) return false;

    g_m3i_v3_pid = pid;
    g_m3i_v3_process = process;
    Log("[feed] M3I-C v3: attached GTAIV.exe pid=%lu for direct viewport memory scan",
        static_cast<unsigned long>(pid));
    return true;
}

static bool M3iV3ReadDirectViewport(uintptr_t address, M3iViewportValues &v)
{
    if (g_m3i_v3_process == nullptr || address == 0) return false;
    v.viewport = address;
    if (!M3iReadRemote(g_m3i_v3_process, address + 0x2B0, &v.width, sizeof(v.width))) return false;
    if (!M3iReadRemote(g_m3i_v3_process, address + 0x2B4, &v.height, sizeof(v.height))) return false;
    if (!M3iReadRemote(g_m3i_v3_process, address + 0x2B8, &v.fov, sizeof(v.fov))) return false;
    if (!M3iReadRemote(g_m3i_v3_process, address + 0x2BC, &v.aspect, sizeof(v.aspect))) return false;
    if (!M3iReadRemote(g_m3i_v3_process, address + 0x2C0, &v.nearClip, sizeof(v.nearClip))) return false;
    if (!M3iReadRemote(g_m3i_v3_process, address + 0x2C4, &v.farClip, sizeof(v.farClip))) return false;

    if (g.width == 0 || g.height == 0) return false;
    if (v.width != static_cast<int>(g.width) || v.height != static_cast<int>(g.height)) return false;
    if (!(v.fov > 0.001f && v.fov < 200.0f)) return false;
    if (!(v.aspect > 0.25f && v.aspect < 5.0f)) return false;
    if (!(v.nearClip > 0.00001f && v.nearClip < 100.0f)) return false;
    if (!(v.farClip > v.nearClip && v.farClip < 1000000.0f)) return false;
    return true;
}

static bool M3iV3AlreadyHave(uintptr_t address)
{
    for (const auto &c : g_m3i_v3_candidates)
        if (c.address == address) return true;
    return false;
}

static bool M3iV3WritableProtect(DWORD protect)
{
    const DWORD p = protect & 0xFFu;
    return p == PAGE_READWRITE || p == PAGE_WRITECOPY ||
           p == PAGE_EXECUTE_READWRITE || p == PAGE_EXECUTE_WRITECOPY;
}

static void M3iV3Scan(bool writableOnly)
{
    if (!M3iV3AttachProcess() || g.width == 0 || g.height == 0) return;

    ++g_m3i_v3_scanAttempt;
    const uintptr_t maxAddress = 0xFFFFFFFFull;
    uintptr_t p = 0x10000;
    size_t regions = 0;
    size_t bytesRead = 0;
    size_t resolutionHits = 0;
    size_t readFailures = 0;
    const size_t chunkSize = 1024 * 1024;

    while (p < maxAddress)
    {
        MEMORY_BASIC_INFORMATION mbi = {};
        if (VirtualQueryEx(g_m3i_v3_process, reinterpret_cast<LPCVOID>(p), &mbi, sizeof(mbi)) == 0)
            break;

        const uintptr_t regionStart = reinterpret_cast<uintptr_t>(mbi.BaseAddress);
        uintptr_t regionEnd = regionStart + mbi.RegionSize;
        if (regionEnd <= p) break;
        if (regionEnd > maxAddress) regionEnd = maxAddress;

        const DWORD prot = mbi.Protect & 0xFFu;
        const bool readable = mbi.State == MEM_COMMIT && prot != PAGE_NOACCESS &&
                              (mbi.Protect & PAGE_GUARD) == 0;
        const bool eligible = readable && (!writableOnly || M3iV3WritableProtect(mbi.Protect));

        if (eligible)
        {
            ++regions;
            for (uintptr_t chunkStart = regionStart; chunkStart < regionEnd; )
            {
                const size_t want = static_cast<size_t>((regionEnd - chunkStart) > chunkSize ? chunkSize : (regionEnd - chunkStart));
                if (want < 8) break;

                std::vector<unsigned char> buffer(want);
                SIZE_T got = 0;
                if (ReadProcessMemory(g_m3i_v3_process, reinterpret_cast<LPCVOID>(chunkStart), buffer.data(), want, &got) && got >= 8)
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
                        if (M3iV3AlreadyHave(candidateAddress)) continue;

                        M3iViewportValues v = {};
                        if (!M3iV3ReadDirectViewport(candidateAddress, v)) continue;

                        M3iV3Candidate c = {};
                        c.address = candidateAddress;
                        c.last = v;
                        c.haveLast = true;
                        g_m3i_v3_candidates.push_back(c);
                        Log("[feed] M3I-C v3: CANDIDATE #%llu address=0x%llX size=%dx%d rawFov=%.9f degIfRad=%.6f aspect=%.9f near=%.9f far=%.6f",
                            static_cast<unsigned long long>(g_m3i_v3_candidates.size()),
                            static_cast<unsigned long long>(candidateAddress),
                            v.width, v.height, v.fov, v.fov * 57.29577951308232f,
                            v.aspect, v.nearClip, v.farClip);
                        if (g_m3i_v3_candidates.size() >= 64) break;
                    }
                }
                else
                {
                    ++readFailures;
                }

                if (g_m3i_v3_candidates.size() >= 64) break;
                chunkStart += want;
            }
        }

        if (g_m3i_v3_candidates.size() >= 64) break;
        p = regionEnd;
    }

    Log("[feed] M3I-C v3: scan complete attempt=%u mode=%s regions=%llu bytes=%llu resolutionHits=%llu candidates=%llu readFailures=%llu",
        g_m3i_v3_scanAttempt, writableOnly ? "writable" : "all-readable",
        static_cast<unsigned long long>(regions),
        static_cast<unsigned long long>(bytesRead),
        static_cast<unsigned long long>(resolutionHits),
        static_cast<unsigned long long>(g_m3i_v3_candidates.size()),
        static_cast<unsigned long long>(readFailures));
}

static void M3iViewportMemScanV3Tick()
{
    const ULONGLONG now = GetTickCount64();

    if (g_m3i_v3_candidates.empty() && now >= g_m3i_v3_nextScanMs)
    {
        g_m3i_v3_nextScanMs = now + 5000;
        // First two passes stay on writable memory to keep the diagnostic cheap.
        // If those fail, broaden once to all committed readable memory.
        const bool writableOnly = g_m3i_v3_scanAttempt < 2;
        M3iV3Scan(writableOnly);
    }

    if (g_m3i_v3_candidates.empty() || now < g_m3i_v3_nextPollMs) return;
    g_m3i_v3_nextPollMs = now + 250;

    for (size_t i = 0; i < g_m3i_v3_candidates.size(); ++i)
    {
        auto &c = g_m3i_v3_candidates[i];
        M3iViewportValues v = {};
        if (!M3iV3ReadDirectViewport(c.address, v)) continue;

        const bool changed = !c.haveLast ||
            fabsf(v.fov - c.last.fov) > 0.0001f ||
            fabsf(v.aspect - c.last.aspect) > 0.0001f ||
            fabsf(v.nearClip - c.last.nearClip) > 0.00001f ||
            fabsf(v.farClip - c.last.farClip) > 0.01f;

        if (changed)
        {
            Log("[feed] M3I-C v3: CHANGE candidate=%llu address=0x%llX rawFov=%.9f degIfRad=%.6f aspect=%.9f near=%.9f far=%.6f",
                static_cast<unsigned long long>(i + 1),
                static_cast<unsigned long long>(c.address),
                v.fov, v.fov * 57.29577951308232f,
                v.aspect, v.nearClip, v.farClip);
            c.last = v;
            c.haveLast = true;
        }
    }
}

'@
    $text = $text.Insert($pos, $helper)
}

# V3 supersedes the expensive V1/V2 signature scans during runtime. Keep their
# code compiled for provenance, but call only the direct structure scan.
$old = "    *op = {};`n    M3iViewportDiagnosticV2Tick();`n    M3iViewportAuditTick();"
$new = "    *op = {};`n    M3iViewportMemScanV3Tick();"
if ($text.Contains($old)) {
    $text = $text.Replace($old, $new)
} elseif (!$text.Contains('M3iViewportMemScanV3Tick();')) {
    throw 'M3I-C v3 call anchor not found'
}

Write-Normalized $cpp $text
Write-Host 'Applied M3I-C v3 direct viewport-structure memory scan + change monitor.'
