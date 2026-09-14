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

if (!$text.Contains('// M3I-C v2 relaxed viewport locator')) {
    $anchor = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
    $pos = $text.IndexOf($anchor)
    if ($pos -lt 0) { throw 'M3I-C v2 anchor not found: M2bBuildConstants' }

    $helper = @'
// M3I-C v2 relaxed viewport locator.
// Diagnostic only. If FusionFix's exact signature has changed in this executable,
// scan x86 absolute MOV loads and accept only candidates whose pointee looks exactly
// like a live rage::grcViewport. Logs enough detail to distinguish process/module/
// signature/validation failures without changing any DLSS-G values.
static bool M3iV2TryCandidate(uintptr_t globalAddress, const char *kind, uintptr_t instructionAddress)
{
    if (globalAddress == 0 || g_m3i_c_viewport.process == nullptr) return false;

    uint32_t viewport32 = 0;
    if (!M3iReadRemote(g_m3i_c_viewport.process, globalAddress, &viewport32, sizeof(viewport32)) || viewport32 == 0)
        return false;

    M3iViewportValues v = {};
    if (!M3iReadViewportValues(globalAddress, v))
        return false;

    // Strong extra guard for the relaxed scan: require the live game's viewport size.
    if (g.width > 0 && g.height > 0 && (v.width != static_cast<int>(g.width) || v.height != static_cast<int>(g.height)))
        return false;

    g_m3i_c_viewport.currentViewportGlobal = globalAddress;
    g_m3i_c_viewport.haveLast = false;
    Log("[feed] M3I-C v2: FOUND %s candidate instr=0x%llX global=0x%llX viewport=0x%llX size=%dx%d rawFov=%.9f degIfRad=%.6f aspect=%.9f near=%.9f far=%.6f",
        kind,
        static_cast<unsigned long long>(instructionAddress),
        static_cast<unsigned long long>(globalAddress),
        static_cast<unsigned long long>(v.viewport),
        v.width, v.height, v.fov, v.fov * 57.29577951308232f,
        v.aspect, v.nearClip, v.farClip);
    return true;
}

static void M3iViewportDiagnosticV2Tick()
{
    static bool completed = false;
    static ULONGLONG nextAttempt = 0;
    static unsigned attempt = 0;
    if (completed || g_m3i_c_viewport.currentViewportGlobal != 0) return;

    const ULONGLONG now = GetTickCount64();
    if (now < nextAttempt) return;
    nextAttempt = now + 2000;
    ++attempt;

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

    if (pid == 0)
    {
        if (attempt <= 3) Log("[feed] M3I-C v2: attempt=%u GTAIV.exe process not found", attempt);
        return;
    }

    HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (process == nullptr)
    {
        if (attempt <= 3) Log("[feed] M3I-C v2: attempt=%u OpenProcess(pid=%lu) failed err=%lu", attempt,
            static_cast<unsigned long>(pid), static_cast<unsigned long>(GetLastError()));
        return;
    }

    uintptr_t base = 0;
    size_t imageSize = 0;
    DWORD moduleErr = ERROR_SUCCESS;
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
        else moduleErr = GetLastError();
        CloseHandle(ms);
    }
    else moduleErr = GetLastError();

    if (base == 0 || imageSize == 0)
    {
        if (attempt <= 3) Log("[feed] M3I-C v2: attempt=%u module enumeration failed pid=%lu err=%lu",
            attempt, static_cast<unsigned long>(pid), static_cast<unsigned long>(moduleErr));
        CloseHandle(process);
        return;
    }

    // Adopt the handle so the existing M3I-C read helper can validate candidates.
    if (g_m3i_c_viewport.process != nullptr && g_m3i_c_viewport.process != process)
        CloseHandle(g_m3i_c_viewport.process);
    g_m3i_c_viewport.pid = pid;
    g_m3i_c_viewport.process = process;
    g_m3i_c_viewport.moduleBase = base;
    g_m3i_c_viewport.moduleSize = imageSize;

    size_t readableBytes = 0;
    size_t exactHits = 0;
    size_t relaxedMovLoads = 0;
    size_t readFailures = 0;
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
        const bool readable = mbi.State == MEM_COMMIT && prot != PAGE_NOACCESS &&
                              (mbi.Protect & PAGE_GUARD) == 0;
        if (readable && regionEnd > p)
        {
            const uintptr_t readStart = p > regionStart ? p : regionStart;
            const size_t bytes = static_cast<size_t>(regionEnd - readStart);
            std::vector<unsigned char> buffer(bytes);
            SIZE_T got = 0;
            if (ReadProcessMemory(process, reinterpret_cast<LPCVOID>(readStart), buffer.data(), bytes, &got) && got >= 6)
            {
                readableBytes += static_cast<size_t>(got);

                // First pass: FusionFix's exact two variants.
                for (size_t i = 0; i + 8 <= static_cast<size_t>(got); ++i)
                {
                    if (buffer[i] != 0x8B || (buffer[i + 1] != 0x35 && buffer[i + 1] != 0x3D)) continue;
                    uint32_t imm = 0;
                    memcpy(&imm, buffer.data() + i + 2, sizeof(imm));
                    ++relaxedMovLoads;

                    if (buffer[i + 6] == 0x75 && buffer[i + 7] == 0x14)
                    {
                        ++exactHits;
                        if (M3iV2TryCandidate(static_cast<uintptr_t>(imm), "exact", readStart + i))
                        {
                            completed = true;
                            return;
                        }
                    }
                }

                // Second pass: same x86 absolute MOV form, but do not require the branch bytes.
                // The viewport-size/FOV/aspect/near/far validation above makes false positives unlikely.
                for (size_t i = 0; i + 6 <= static_cast<size_t>(got); ++i)
                {
                    if (buffer[i] != 0x8B || (buffer[i + 1] != 0x35 && buffer[i + 1] != 0x3D)) continue;
                    uint32_t imm = 0;
                    memcpy(&imm, buffer.data() + i + 2, sizeof(imm));
                    if (M3iV2TryCandidate(static_cast<uintptr_t>(imm), "relaxed", readStart + i))
                    {
                        completed = true;
                        return;
                    }
                }
            }
            else ++readFailures;
        }

        if (regionEnd <= p) break;
        p = regionEnd;
    }

    Log("[feed] M3I-C v2: scan miss attempt=%u pid=%lu base=0x%llX size=%llu readable=%llu exactHits=%llu movAbsLoads=%llu readFailures=%llu",
        attempt, static_cast<unsigned long>(pid), static_cast<unsigned long long>(base),
        static_cast<unsigned long long>(imageSize), static_cast<unsigned long long>(readableBytes),
        static_cast<unsigned long long>(exactHits), static_cast<unsigned long long>(relaxedMovLoads),
        static_cast<unsigned long long>(readFailures));
}

'@
    $text = $text.Insert($pos, $helper)
}

if (!$text.Contains('M3iViewportDiagnosticV2Tick();')) {
    $anchor = "    *op = {};`n    M3iViewportAuditTick();"
    $replacement = "    *op = {};`n    M3iViewportDiagnosticV2Tick();`n    M3iViewportAuditTick();"
    if (!$text.Contains($anchor)) { throw 'M3I-C v2 call anchor not found' }
    $text = $text.Replace($anchor, $replacement)
}

Write-Normalized $cpp $text
Write-Host 'Applied M3I-C v2 relaxed viewport locator + detailed diagnostics.'
