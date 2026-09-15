# A2-S2.2 build-only transform: independent multi-pass feature-18 chain.
# Input must already be the generated A2-S2 source from a2-s2-stage.ps1.
# Stable A2-S2 committed/base sources remain untouched.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot
)

$ErrorActionPreference = 'Stop'

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = 0
    $pos = 0
    while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) {
        $count++
        $pos = $i + $Old.Length
    }
    if ($count -ne 1) { throw "A2-S2.2 ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old, $New)
}

$nrPath = Join-Path $GeneratedRoot 'm3k_nr.h'
$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $nrPath) -or -not (Test-Path -LiteralPath $vkPath)) {
    throw "A2-S2.2 generated headers missing under $GeneratedRoot"
}

$nr = [IO.File]::ReadAllText($nrPath)
$vk = [IO.File]::ReadAllText($vkPath)

$classStart = $nr.IndexOf('class M3KNr {', [StringComparison]::Ordinal)
$globalMarker = 'static M3KNr g_m3k;'
$classEnd = $nr.IndexOf($globalMarker, [StringComparison]::Ordinal)
if ($classStart -lt 0 -or $classEnd -le $classStart) {
    throw 'A2-S2.2 could not locate M3KNr class boundaries'
}

$classNew = @'
class M3KNr {
    using Result = unsigned long;
    using Init = Result (__cdecl *)(unsigned long long, const wchar_t *, ID3D12Device *, unsigned long, const void *);
    using Populate = Result (__cdecl *)(void *);
    using Create = Result (__cdecl *)(ID3D12GraphicsCommandList *, int, void *, void **);
    using Eval = Result (__cdecl *)(ID3D12GraphicsCommandList *, const void *, const void *, void *);
    using Release = Result (__cdecl *)(void *);
    using Shutdown = Result (__cdecl *)(ID3D12Device *);
    using BridgeInit = Result (__cdecl *)(Init, unsigned long long, const wchar_t *, ID3D12Device *, unsigned long);
    using BridgePopulate = Result (__cdecl *)(Populate, void *);
    using BridgeCreate = Result (__cdecl *)(Create, ID3D12GraphicsCommandList *, int, void *, void **);
    using BridgeEval = Result (__cdecl *)(Eval, ID3D12GraphicsCommandList *, const void *, const void *);
    using BridgeRelease = Result (__cdecl *)(Release, void *);
    using BridgeShutdown = Result (__cdecl *)(Shutdown, ID3D12Device *);

    static constexpr unsigned MaxPasses = 3;

    struct PassState {
        NVSDK_NGX_Parameter *params = nullptr;
        void *feature = nullptr;
        ID3D12Resource *output = nullptr;
        bool first = true;
        UINT64 evaluations = 0;
    };

    HMODULE runtime_ = nullptr, bridge_ = nullptr;
    ID3D12Device *device_ = nullptr;
    ID3D12CommandQueue *queue_ = nullptr;
    ID3D12CommandAllocator *allocator_ = nullptr;
    ID3D12GraphicsCommandList *initList_ = nullptr;
    ID3D12Fence *fence_ = nullptr;
    HANDLE event_ = nullptr;
    UINT64 fenceValue_ = 0;
    PassState pass_[MaxPasses] = {};
    unsigned passes_ = 1;

    Init init_ = nullptr; Populate populate_ = nullptr; Create create_ = nullptr;
    Eval eval_ = nullptr; Release release_ = nullptr; Shutdown shutdown_ = nullptr;
    BridgeInit bi_ = nullptr; BridgePopulate bp_ = nullptr; BridgeCreate bc_ = nullptr;
    BridgeEval be_ = nullptr; BridgeRelease br_ = nullptr; BridgeShutdown bs_ = nullptr;
    bool attached_ = false, attempted_ = false, failed_ = false;
    unsigned w_ = 0, h_ = 0;
    int flags_ = 0;

    static bool Ok(Result r) { return NVSDK_NGX_SUCCEED(static_cast<NVSDK_NGX_Result>(r)); }
    static bool Report(const char *operation, Result r) {
        Log("M3K-A0: %s result=0x%08lX (%s)", operation, r, NgxResultName(static_cast<NVSDK_NGX_Result>(r)));
        return Ok(r);
    }
    template<class T> static void Drop(T *&p) { if (p) { p->Release(); p = nullptr; } }
    template<class T> static T Export(HMODULE m, const char *key) {
        return m ? reinterpret_cast<T>(GetProcAddress(m, key)) : nullptr;
    }

    Result AttachGuarded(const wchar_t *path, DWORD *exception) {
        __try { return bi_(init_, m3k::SnippetAppId, path, device_, NVSDK_NGX_Version_API); }
        __except(EXCEPTION_EXECUTE_HANDLER) { *exception = GetExceptionCode(); return 0xBAD00000UL; }
    }
    Result PopulateGuarded(unsigned index, DWORD *exception) {
        __try { return bp_(populate_, pass_[index].params); }
        __except(EXCEPTION_EXECUTE_HANDLER) { *exception = GetExceptionCode(); return 0xBAD00000UL; }
    }
    Result CreateGuarded(unsigned index, DWORD *exception) {
        __try { return bc_(create_, initList_, m3k::FeatureId, pass_[index].params, &pass_[index].feature); }
        __except(EXCEPTION_EXECUTE_HANDLER) { *exception = GetExceptionCode(); return 0xBAD00000UL; }
    }
    Result EvalGuarded(unsigned index, ID3D12GraphicsCommandList *list, DWORD *exception) {
        __try { return be_(eval_, list, pass_[index].feature, pass_[index].params); }
        __except(EXCEPTION_EXECUTE_HANDLER) { *exception = GetExceptionCode(); return 0xBAD00000UL; }
    }

    bool ReleaseGuarded() {
        __try {
            for (int i = int(MaxPasses) - 1; i >= 0; --i) {
                if (pass_[i].feature) {
                    Result r = br_(release_, pass_[i].feature);
                    Log("M3K-MP: feature 18 pass %d release result=0x%08lX (%s)",
                        i + 1, r, NgxResultName(static_cast<NVSDK_NGX_Result>(r)));
                    if (!Ok(r)) return false;
                    pass_[i].feature = nullptr;
                }
            }
            for (int i = int(MaxPasses) - 1; i >= 0; --i) {
                if (pass_[i].params) {
                    auto r = NVSDK_NGX_D3D12_DestroyParameters(pass_[i].params);
                    Log("M3K-MP: pass %d parameter destroy result=0x%08lX (%s)",
                        i + 1, static_cast<unsigned long>(r), NgxResultName(r));
                    if (!NVSDK_NGX_SUCCEED(r)) return false;
                    pass_[i].params = nullptr;
                }
            }
            if (attached_) {
                if (!Report("NR snippet shutdown (Feeder core retained)", bs_(shutdown_, device_))) return false;
                attached_ = false;
            }
            return true;
        } __except(EXCEPTION_EXECUTE_HANDLER) {
            Log("M3K-MP: cleanup exception=0x%08lX; retaining runtime until process exit", GetExceptionCode());
            return false;
        }
    }

    bool Retire() {
        if (!queue_ || !fence_) return true;
        UINT64 value = ++fenceValue_;
        HRESULT hr = queue_->Signal(fence_, value);
        if (SUCCEEDED(hr) && fence_->GetCompletedValue() < value) {
            hr = fence_->SetEventOnCompletion(value, event_);
            if (SUCCEEDED(hr) && WaitForSingleObject(event_, 10000) != WAIT_OBJECT_0)
                hr = HRESULT_FROM_WIN32(WAIT_TIMEOUT);
        }
        if (FAILED(hr) || FAILED(device_->GetDeviceRemovedReason())) {
            Log("M3K-MP: GPU retirement failed hr=0x%08lX; NR bypassed, retaining resources", hr);
            failed_ = true;
            return false;
        }
        return true;
    }

    bool MakeOutput(unsigned index) {
        if (index >= passes_) return false;
        if (pass_[index].output) return true;
        DXGI_FORMAT format = (flags_ & NVSDK_NGX_DLSS_Feature_Flags_IsHDR)
            ? DXGI_FORMAT_R16G16B16A16_FLOAT : DXGI_FORMAT_R8G8B8A8_UNORM;
        D3D12_FEATURE_DATA_FORMAT_SUPPORT support = {format};
        if (FAILED(device_->CheckFeatureSupport(D3D12_FEATURE_FORMAT_SUPPORT, &support, sizeof(support))) ||
            !(support.Support2 & D3D12_FORMAT_SUPPORT2_UAV_TYPED_STORE)) return false;
        D3D12_HEAP_PROPERTIES heap = {}; heap.Type = D3D12_HEAP_TYPE_DEFAULT;
        D3D12_RESOURCE_DESC desc = {};
        desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        desc.Width = w_; desc.Height = h_; desc.DepthOrArraySize = 1; desc.MipLevels = 1;
        desc.Format = format; desc.SampleDesc.Count = 1;
        desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
        HRESULT hr = device_->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &desc,
            D3D12_RESOURCE_STATE_UNORDERED_ACCESS, nullptr, IID_PPV_ARGS(&pass_[index].output));
        Log("M3K-MP: NR pass %u output %ux%u format=%u UAV allocation hr=0x%08lX",
            index + 1, w_, h_, unsigned(format), hr);
        if (FAILED(hr)) return false;
        wchar_t name[64] = {};
        swprintf_s(name, L"M3K feature 18 pass %u output", index + 1);
        pass_[index].output->SetName(name);
        return true;
    }

    void Transition(unsigned index, ID3D12GraphicsCommandList *list,
                    D3D12_RESOURCE_STATES before, D3D12_RESOURCE_STATES after) {
        if (index >= passes_ || !pass_[index].output) return;
        D3D12_RESOURCE_BARRIER b = {};
        b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Transition.pResource = pass_[index].output;
        b.Transition.StateBefore = before;
        b.Transition.StateAfter = after;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        list->ResourceBarrier(1, &b);
    }

public:
    bool ShutdownRuntime(bool dying = false) {
        if (dying && attempted_) {
            Log("M3K-MP: process teardown; runtime calls skipped, resources retained until exit");
            failed_ = true; return false;
        }
        if (!Retire() || !ReleaseGuarded()) { failed_ = true; return false; }
        for (unsigned i = 0; i < MaxPasses; ++i) Drop(pass_[i].output);
        Drop(initList_); Drop(allocator_); Drop(fence_);
        if (event_) CloseHandle(event_);
        event_ = nullptr;
        Drop(queue_); Drop(device_);
        if (runtime_) FreeLibrary(runtime_);
        if (bridge_) FreeLibrary(bridge_);
        *this = M3KNr{};
        return true;
    }

    bool Prepare(HMODULE owner, ID3D12Device *device, ID3D12CommandQueue *queue,
                 unsigned w, unsigned h, int flags, unsigned requestedPasses = 1) {
        if (requestedPasses < 1) requestedPasses = 1;
        if (requestedPasses > MaxPasses) requestedPasses = MaxPasses;
        if (attempted_ && device_ &&
            (device_ != device || w_ != w || h_ != h || flags_ != flags || passes_ != requestedPasses)) {
            Log("M3K-MP: contract changed; rebuilding feature 18 chain (%u -> %u passes)", passes_, requestedPasses);
            if (!ShutdownRuntime()) return false;
        }
        if (attempted_)
            return Ready() && device_ == device && w_ == w && h_ == h && flags_ == flags && passes_ == requestedPasses;
        attempted_ = true; failed_ = true;
        w_ = w; h_ = h; flags_ = flags; passes_ = requestedPasses;

        wchar_t base[MAX_PATH] = {}, path[MAX_PATH] = {}, shim[MAX_PATH] = {};
        if (!GetModuleFileNameW(owner, base, MAX_PATH) || !wcsrchr(base, L'\\')) return false;
        *wcsrchr(base, L'\\') = 0;
        if (_snwprintf_s(path, _TRUNCATE, L"%s\\m3k\\nvngx_dlssnr.dll", base) < 0 ||
            _snwprintf_s(shim, _TRUNCATE, L"%s\\m3k\\m3k-nvngx.dll", base) < 0) return false;
        if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES) {
            Log("M3K-A0: DLSS NR runtime missing: %ls; NR bypass active", path); return false;
        }
        Log("M3K-MP: DLSS NR runtime found: %ls; requested independent passes=%u", path, passes_);
        if (GetModuleHandleW(L"nvngx_dlssnr.dll")) {
            Log("M3K-MP: NR runtime already loaded by another provider; bypass"); return false;
        }
        runtime_ = LoadLibraryExW(path, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
        if (!runtime_) { Log("M3K-MP: runtime load failed error=%lu", GetLastError()); return false; }
        bridge_ = LoadLibraryExW(shim, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
        init_ = Export<Init>(runtime_, "NVSDK_NGX_D3D12_Init_Ext");
        populate_ = Export<Populate>(runtime_, "NVSDK_NGX_D3D12_PopulateParameters_Impl");
        create_ = Export<Create>(runtime_, "NVSDK_NGX_D3D12_CreateFeature");
        eval_ = Export<Eval>(runtime_, "NVSDK_NGX_D3D12_EvaluateFeature");
        release_ = Export<Release>(runtime_, "NVSDK_NGX_D3D12_ReleaseFeature");
        shutdown_ = Export<Shutdown>(runtime_, "NVSDK_NGX_D3D12_Shutdown1");
        bi_ = Export<BridgeInit>(bridge_, "M3K_Init"); bp_ = Export<BridgePopulate>(bridge_, "M3K_Populate");
        bc_ = Export<BridgeCreate>(bridge_, "M3K_Create"); be_ = Export<BridgeEval>(bridge_, "M3K_Evaluate");
        br_ = Export<BridgeRelease>(bridge_, "M3K_Release"); bs_ = Export<BridgeShutdown>(bridge_, "M3K_Shutdown");
        if (!init_ || !populate_ || !create_ || !eval_ || !release_ || !shutdown_ ||
            !bi_ || !bp_ || !bc_ || !be_ || !br_ || !bs_) {
            Log("M3K-MP: required runtime/shim export missing; NR bypass active"); return false;
        }

        device_ = device; device_->AddRef(); queue_ = queue; queue_->AddRef();
        DWORD exception = 0;
        Result r = AttachGuarded(path, &exception);
        if (!Report("snippet Init_Ext (reuse Feeder D3D12/NGX core)", r) || exception) {
            Log("M3K-MP: attach failed exception=0x%08lX; NR bypass active", exception); return false;
        }
        attached_ = true;
        if (FAILED(device_->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator_))) ||
            FAILED(device_->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator_, nullptr, IID_PPV_ARGS(&initList_))) ||
            FAILED(device_->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence_)))) return false;
        event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (!event_) return false;

        for (unsigned i = 0; i < passes_; ++i) {
            exception = 0;
            auto allocResult = NVSDK_NGX_D3D12_AllocateParameters(&pass_[i].params);
            Log("M3K-MP: pass %u allocate parameters result=0x%08lX (%s)",
                i + 1, static_cast<unsigned long>(allocResult), NgxResultName(allocResult));
            if (!NVSDK_NGX_SUCCEED(allocResult) || !pass_[i].params) return false;
            auto populateResult = PopulateGuarded(i, &exception);
            Log("M3K-MP: pass %u PopulateParameters_Impl result=0x%08lX exception=0x%08lX",
                i + 1, populateResult, exception);
            if (!Ok(populateResult) || exception) return false;
            m3k::CreateContract(pass_[i].params, w, h, flags);
            exception = 0;
            r = CreateGuarded(i, &exception);
            Log("M3K-MP: feature 18 pass %u/%u create result=0x%08lX exception=0x%08lX handle=%p; %ux%u -> %ux%u",
                i + 1, passes_, r, exception, pass_[i].feature, w, h, w, h);
            if (!Ok(r) || exception || !pass_[i].feature || FAILED(initList_->Close())) return false;
            ID3D12CommandList *lists[] = {initList_};
            queue_->ExecuteCommandLists(1, lists);
            if (!Retire()) return false;
            if (i + 1 < passes_) {
                if (FAILED(allocator_->Reset()) || FAILED(initList_->Reset(allocator_, nullptr))) return false;
            }
        }

        failed_ = false;
        Log("M3K-MP: independent feature 18 chain creation SUCCESS passes=%u", passes_);
        return true;
    }

    bool Ready() const {
        if (failed_ || passes_ < 1 || passes_ > MaxPasses) return false;
        for (unsigned i = 0; i < passes_; ++i) if (!pass_[i].feature) return false;
        return true;
    }
    unsigned PassCount() const { return passes_; }
    void ResetHistory() { for (unsigned i = 0; i < MaxPasses; ++i) pass_[i].first = true; }

    int Evaluate(ID3D12GraphicsCommandList *list, const NVSDK_NGX_D3D12_DLSS_Eval_Params &ep) {
        if (!Ready()) return 0;
        ID3D12Resource *color = ep.Feature.pInColor;
        ID3D12Resource *depth = ep.pInDepth;
        ID3D12Resource *mv = ep.pInMotionVectors;
        if (!color || !depth || !mv) { failed_ = true; Log("M3K-MP: missing same-frame guide; NR bypassed"); return 0; }
        const auto cd = color->GetDesc(), dd = depth->GetDesc(), md = mv->GetDesc();
        const bool valid = cd.Width >= w_ && cd.Height >= h_ && dd.Width >= w_ && dd.Height >= h_ &&
            md.Width >= w_ && md.Height >= h_ && dd.Format == DXGI_FORMAT_R32_FLOAT && md.Format == DXGI_FORMAT_R16G16_FLOAT &&
            cd.SampleDesc.Count == 1 && dd.SampleDesc.Count == 1 && md.SampleDesc.Count == 1 &&
            (cd.Format == DXGI_FORMAT_B8G8R8A8_UNORM || cd.Format == DXGI_FORMAT_R8G8B8A8_UNORM || cd.Format == DXGI_FORMAT_R16G16B16A16_FLOAT);
        if (!valid) { failed_ = true; Log("M3K-MP: unsupported shared texture contract; NR bypassed"); return 0; }
        if (cd.Width != w_ || cd.Height != h_ || dd.Width != w_ || dd.Height != h_ || md.Width != w_ || md.Height != h_) {
            static bool saidSubrect = false;
            if (!saidSubrect) {
                saidSubrect = true;
                Log("M3K-A2-S2.2: %u NR passes use %ux%u subrect inside shared color=%llux%u depth=%llux%u mv=%llux%u resources",
                    passes_, w_, h_, static_cast<unsigned long long>(cd.Width), cd.Height,
                    static_cast<unsigned long long>(dd.Width), dd.Height,
                    static_cast<unsigned long long>(md.Width), md.Height);
            }
        }
        for (unsigned i = 0; i < passes_; ++i) {
            if (!MakeOutput(i)) { failed_ = true; Log("M3K-MP: pass %u output allocation failed; NR bypassed", i + 1); return 0; }
        }

        ID3D12Resource *currentColor = color;
        for (unsigned i = 0; i < passes_; ++i) {
            PassState &state = pass_[i];
            const bool reset = state.first || ep.InReset;
            m3k::EvalContract(state.params, currentColor, state.output, depth, mv, w_, h_, reset,
                (flags_ & NVSDK_NGX_DLSS_Feature_Flags_DepthInverted) != 0,
                ep.InJitterOffsetX, ep.InJitterOffsetY, ep.InMVScaleX, ep.InMVScaleY,
                ep.InPreExposure, ep.InExposureScale);
            DWORD exception = 0;
            Result r = EvalGuarded(i, list, &exception);
            ++state.evaluations;
            if (state.evaluations == 1 || state.evaluations % 300 == 0 || !Ok(r) || exception)
                Log("M3K-MP: feature 18 pass %u/%u evaluation %s result=0x%08lX exception=0x%08lX frame=%llu %ux%u reset=%d",
                    i + 1, passes_, Ok(r) && !exception ? "SUCCESS" : "FAILED", r, exception,
                    state.evaluations, w_, h_, int(reset));
            if (!Ok(r) || exception) { failed_ = true; ResetHistory(); return -1; }
            Transition(i, list, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
            if (i > 0)
                Transition(i - 1, list, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
            state.first = false;
            currentColor = state.output;
        }
        return 1;
    }

    ID3D12Resource *Output() const {
        return (passes_ >= 1 && passes_ <= MaxPasses) ? pass_[passes_ - 1].output : nullptr;
    }
    void Finish(ID3D12GraphicsCommandList *list) {
        if (passes_ < 1 || passes_ > MaxPasses) return;
        Transition(passes_ - 1, list, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    }
};
'@

$nr = $nr.Substring(0, $classStart) + $classNew + "`r`n`r`n" + $nr.Substring($classEnd)

$vk = Replace-ExactOnce $vk `
    'static bool g_m3kArmed = false, g_m3kWasUsed = false;' `
    "static bool g_m3kArmed = false, g_m3kWasUsed = false;`r`nstatic UINT g_m3kNrPasses = 1;" `
    'global NR pass count'

$pollOld = @'
        const UINT requested = GetPrivateProfileIntW(L"M3K", L"Mode", 0, path);
        const int mode = requested <= 2 ? int(requested) : 0;
'@
$pollNew = @'
        const UINT requested = GetPrivateProfileIntW(L"M3K", L"Mode", 0, path);
        const int mode = requested <= 2 ? int(requested) : 0;
        const UINT requestedPasses = GetPrivateProfileIntW(L"M3K", L"NRPasses", 1, path);
        const UINT nrPasses = requestedPasses < 1 ? 1 : (requestedPasses > 3 ? 3 : requestedPasses);
        static bool nrPassFirst = true;
        if (nrPassFirst || nrPasses != g_m3kNrPasses) {
            Log("M3K-A2-S2.2: NRPasses=%u (independent feature18 instances; allowed 1..3)", nrPasses);
            g_m3kNrPasses = nrPasses;
            g_m3k.ResetHistory();
            nrPassFirst = false;
        }
'@
$vk = Replace-ExactOnce $vk $pollOld $pollNew 'INI NRPasses polling'

$vk = Replace-ExactOnce $vk `
    'g_m3k.Prepare(g_self, g.dev12, g.queue, g_m3kSrW, g_m3kSrH, g.create_flags);' `
    'g_m3k.Prepare(g_self, g.dev12, g.queue, g_m3kSrW, g_m3kSrH, g.create_flags, g_m3kNrPasses);' `
    'low-res multipass Prepare'

$vk = Replace-ExactOnce $vk `
    'g_m3k.Prepare(g_self, g.dev12, g.queue, g.width, g.height, g.create_flags);' `
    'g_m3k.Prepare(g_self, g.dev12, g.queue, g.width, g.height, g.create_flags, g_m3kNrPasses);' `
    'native multipass Prepare'

$logOld = @'
            Log("M3K-A2-S2: %s -> DLSS SR running %ux%u -> %ux%u result=0x%08X reset=%d mvScale=(%.3f,%.3f) jitter=(0,0)",
                used ? "NR18" : "RAW", g_m3kSrW, g_m3kSrH, g_m3kSrOutW, g_m3kSrOutH,
                result, sr.InReset, sr.InMVScaleX, sr.InMVScaleY);
'@
$logNew = @'
            Log("M3K-A2-S2.2: %s passes=%u -> DLSS SR running %ux%u -> %ux%u result=0x%08X reset=%d mvScale=(%.3f,%.3f) jitter=(0,0)",
                used ? "NR18" : "RAW", used ? g_m3k.PassCount() : 0u,
                g_m3kSrW, g_m3kSrH, g_m3kSrOutW, g_m3kSrOutH,
                result, sr.InReset, sr.InMVScaleX, sr.InMVScaleY);
'@
$vk = Replace-ExactOnce $vk $logOld $logNew 'periodic multipass SR log'

[IO.File]::WriteAllText($nrPath, $nr, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($vkPath, $vk, (New-Object Text.UTF8Encoding($false)))

$verify = [IO.File]::ReadAllText($nrPath) + [IO.File]::ReadAllText($vkPath)
foreach ($marker in @(
    'static constexpr unsigned MaxPasses = 3;',
    'independent feature 18 chain creation SUCCESS',
    'M3K-A2-S2.2: NRPasses=%u',
    'g.create_flags, g_m3kNrPasses',
    'M3K-A2-S2.2: %s passes=%u -> DLSS SR running')) {
    if ($verify.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "A2-S2.2 verification marker missing: $marker"
    }
}

Write-Host "A2-S2.2 multi-pass generated source ready: $GeneratedRoot"
Write-Host 'Architecture: separate feature18 handle/params/output/history per pass; max 3.'
