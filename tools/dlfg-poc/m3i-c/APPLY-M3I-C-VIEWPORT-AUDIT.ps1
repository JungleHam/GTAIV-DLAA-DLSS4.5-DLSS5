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

if (!$text.Contains('// M3I-C remote GTA IV viewport audit')) {
    if (!$text.Contains('#include <vector>')) {
        $anchor = '#include <string>'
        if (!$text.Contains($anchor)) { throw 'M3I-C include anchor not found: #include <string>' }
        $text = $text.Replace($anchor, "#include <string>`n#include <vector>`n#include <tlhelp32.h>`n#include <cwchar>")
    }

    $anchor = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
    $pos = $text.IndexOf($anchor)
    if ($pos -lt 0) { throw 'M3I-C anchor not found: M2bBuildConstants' }

    $helper = @'
// M3I-C remote GTA IV viewport audit.
// Diagnostic only. Reads GTAIV.exe's current rage::grcViewport using the same
// current-viewport signature documented by FusionFix. Nothing here changes NGX inputs.
struct M3iViewportValues
{
    int width = 0;
    int height = 0;
    float fov = 0.0f;
    float aspect = 0.0f;
    float nearClip = 0.0f;
    float farClip = 0.0f;
    uintptr_t viewport = 0;
};

struct M3iViewportAuditState
{
    DWORD pid = 0;
    HANDLE process = nullptr;
    uintptr_t moduleBase = 0;
    size_t moduleSize = 0;
    uintptr_t currentViewportGlobal = 0;
    ULONGLONG nextRetryMs = 0;
    ULONGLONG nextReadMs = 0;
    bool loggedFailure = false;
    bool haveLast = false;
    M3iViewportValues last = {};
};

static M3iViewportAuditState g_m3i_c_viewport = {};

static bool M3iReadRemote(HANDLE process, uintptr_t address, void *dst, size_t size)
{
    SIZE_T got = 0;
    return process != nullptr && address != 0 && dst != nullptr && size != 0 &&
           ReadProcessMemory(process, reinterpret_cast<LPCVOID>(address), dst, size, &got) != FALSE && got == size;
}

static bool M3iReadViewportValues(uintptr_t globalAddress, M3iViewportValues &v)
{
    if (g_m3i_c_viewport.process == nullptr || globalAddress == 0) return false;

    uint32_t viewport32 = 0;
    if (!M3iReadRemote(g_m3i_c_viewport.process, globalAddress, &viewport32, sizeof(viewport32)) || viewport32 == 0)
        return false;

    v.viewport = static_cast<uintptr_t>(viewport32);
    if (!M3iReadRemote(g_m3i_c_viewport.process, v.viewport + 0x2B0, &v.width, sizeof(v.width))) return false;
    if (!M3iReadRemote(g_m3i_c_viewport.process, v.viewport + 0x2B4, &v.height, sizeof(v.height))) return false;
    if (!M3iReadRemote(g_m3i_c_viewport.process, v.viewport + 0x2B8, &v.fov, sizeof(v.fov))) return false;
    if (!M3iReadRemote(g_m3i_c_viewport.process, v.viewport + 0x2BC, &v.aspect, sizeof(v.aspect))) return false;
    if (!M3iReadRemote(g_m3i_c_viewport.process, v.viewport + 0x2C0, &v.nearClip, sizeof(v.nearClip))) return false;
    if (!M3iReadRemote(g_m3i_c_viewport.process, v.viewport + 0x2C4, &v.farClip, sizeof(v.farClip))) return false;

    if (v.width < 320 || v.width > 10000 || v.height < 200 || v.height > 10000) return false;
    if (!(v.fov > 0.001f && v.fov < 200.0f)) return false;
    if (!(v.aspect > 0.25f && v.aspect < 5.0f)) return false;
    if (!(v.nearClip > 0.00001f && v.nearClip < 100.0f)) return false;
    if (!(v.farClip > v.nearClip && v.farClip < 1000000.0f)) return false;
    return true;
}

static bool M3iAttachGtaiv()
{
    if (g_m3i_c_viewport.process != nullptr && g_m3i_c_viewport.currentViewportGlobal != 0)
        return true;

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

    uintptr_t base = 0;
    size_t imageSize = 0;
    HANDLE ms = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (ms != INVALID_HANDLE_VALUE)
    {
        MODULEENTRY32W me = {};
        me.dwSize = sizeof(me);
        if (Module32FirstW(ms, &me))
        {
            do
            {
                if (_wcsicmp(me.szModule, L"GTAIV.exe") == 0)
                {
                    base = reinterpret_cast<uintptr_t>(me.modBaseAddr);
                    imageSize = static_cast<size_t>(me.modBaseSize);
                    break;
                }
            } while (Module32NextW(ms, &me));
        }
        CloseHandle(ms);
    }
    if (base == 0 || imageSize == 0)
    {
        CloseHandle(process);
        return false;
    }

    g_m3i_c_viewport.pid = pid;
    g_m3i_c_viewport.process = process;
    g_m3i_c_viewport.moduleBase = base;
    g_m3i_c_viewport.moduleSize = imageSize;

    uintptr_t p = base;
    const uintptr_t end = base + imageSize;
    while (p < end)
    {
        MEMORY_BASIC_INFORMATION mbi = {};
        if (VirtualQueryEx(process, reinterpret_cast<LPCVOID>(p), &mbi, sizeof(mbi)) == 0) break;

        uintptr_t regionStart = reinterpret_cast<uintptr_t>(mbi.BaseAddress);
        uintptr_t regionEnd = regionStart + mbi.RegionSize;
        if (regionEnd > end) regionEnd = end;

        const DWORD prot = mbi.Protect & 0xFFu;
        const bool readable = mbi.State == MEM_COMMIT &&
            prot != PAGE_NOACCESS && (mbi.Protect & PAGE_GUARD) == 0;

        if (readable && regionEnd > p)
        {
            const uintptr_t readStart = p > regionStart ? p : regionStart;
            const size_t bytes = static_cast<size_t>(regionEnd - readStart);
            std::vector<unsigned char> buffer(bytes);
            SIZE_T got = 0;
            if (ReadProcessMemory(process, reinterpret_cast<LPCVOID>(readStart), buffer.data(), bytes, &got) && got >= 8)
            {
                for (size_t i = 0; i + 8 <= static_cast<size_t>(got); ++i)
                {
                    if (buffer[i] != 0x8B || (buffer[i + 1] != 0x35 && buffer[i + 1] != 0x3D) ||
                        buffer[i + 6] != 0x75 || buffer[i + 7] != 0x14)
                        continue;

                    uint32_t candidate32 = 0;
                    memcpy(&candidate32, buffer.data() + i + 2, sizeof(candidate32));
                    M3iViewportValues test = {};
                    if (candidate32 != 0 && M3iReadViewportValues(static_cast<uintptr_t>(candidate32), test))
                    {
                        g_m3i_c_viewport.currentViewportGlobal = static_cast<uintptr_t>(candidate32);
                        Log("[feed] M3I-C: GTAIV viewport signature found pid=%lu module=0x%llX size=%llu global=0x%llX viewport=0x%llX",
                            static_cast<unsigned long>(pid),
                            static_cast<unsigned long long>(base),
                            static_cast<unsigned long long>(imageSize),
                            static_cast<unsigned long long>(g_m3i_c_viewport.currentViewportGlobal),
                            static_cast<unsigned long long>(test.viewport));
                        return true;
                    }
                }
            }
        }

        if (regionEnd <= p) break;
        p = regionEnd;
    }

    CloseHandle(g_m3i_c_viewport.process);
    g_m3i_c_viewport.process = nullptr;
    g_m3i_c_viewport.pid = 0;
    g_m3i_c_viewport.moduleBase = 0;
    g_m3i_c_viewport.moduleSize = 0;
    return false;
}

static void M3iViewportAuditTick()
{
    const ULONGLONG now = GetTickCount64();
    if (now < g_m3i_c_viewport.nextReadMs) return;
    g_m3i_c_viewport.nextReadMs = now + 250;

    if (!M3iAttachGtaiv())
    {
        if (now >= g_m3i_c_viewport.nextRetryMs)
        {
            g_m3i_c_viewport.nextRetryMs = now + 2000;
            if (!g_m3i_c_viewport.loggedFailure)
            {
                Log("[feed] M3I-C: GTAIV viewport audit waiting for GTAIV.exe/signature");
                g_m3i_c_viewport.loggedFailure = true;
            }
        }
        return;
    }

    M3iViewportValues v = {};
    if (!M3iReadViewportValues(g_m3i_c_viewport.currentViewportGlobal, v))
        return;

    const bool changed = !g_m3i_c_viewport.haveLast ||
        v.width != g_m3i_c_viewport.last.width || v.height != g_m3i_c_viewport.last.height ||
        fabsf(v.fov - g_m3i_c_viewport.last.fov) > 0.0001f ||
        fabsf(v.aspect - g_m3i_c_viewport.last.aspect) > 0.0001f ||
        fabsf(v.nearClip - g_m3i_c_viewport.last.nearClip) > 0.00001f ||
        fabsf(v.farClip - g_m3i_c_viewport.last.farClip) > 0.01f ||
        v.viewport != g_m3i_c_viewport.last.viewport;

    if (changed)
    {
        Log("[feed] M3I-C: GTA viewport=%llX size=%dx%d rawFov=%.9f rawFovDegIfRadians=%.6f aspect=%.9f near=%.9f far=%.6f",
            static_cast<unsigned long long>(v.viewport), v.width, v.height, v.fov,
            v.fov * 57.29577951308232f, v.aspect, v.nearClip, v.farClip);
        g_m3i_c_viewport.last = v;
        g_m3i_c_viewport.haveLast = true;
    }
}

'@
    $text = $text.Insert($pos, $helper)
}

if (!$text.Contains('M3iViewportAuditTick();')) {
    $anchor = "static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)`n{`n    *op = {};"
    $replacement = "static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)`n{`n    *op = {};`n    M3iViewportAuditTick();"
    if (!$text.Contains($anchor)) { throw 'M3I-C call anchor not found: M2bBuildConstants prologue' }
    $text = $text.Replace($anchor, $replacement)
}

Write-Normalized $cpp $text
Write-Host 'Applied M3I-C zero-behaviour-change GTA IV viewport audit.'
