// SPDX-License-Identifier: Apache-2.0
// M3K native NR integration. Contract derived from DLSS5 ReShade AIO;
// Copyright 2026 kibblerz. Modifications Copyright 2026 JungleHam. See ../NOTICE.
// Included in the pinned Feeder TU after Log, NGX headers, and the Feed state.
#pragma once
#include "m3k_contract.h"

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

    HMODULE runtime_ = nullptr, bridge_ = nullptr;
    ID3D12Device *device_ = nullptr; // AddRef: retained if GPU retirement fails
    ID3D12CommandQueue *queue_ = nullptr;
    ID3D12CommandAllocator *allocator_ = nullptr;
    ID3D12GraphicsCommandList *initList_ = nullptr;
    ID3D12Fence *fence_ = nullptr;
    HANDLE event_ = nullptr;
    UINT64 fenceValue_ = 0;
    NVSDK_NGX_Parameter *params_ = nullptr; // separate from DLAA's parameter block
    void *feature_ = nullptr;
    ID3D12Resource *output_ = nullptr;
    Init init_ = nullptr; Populate populate_ = nullptr; Create create_ = nullptr;
    Eval eval_ = nullptr; Release release_ = nullptr; Shutdown shutdown_ = nullptr;
    BridgeInit bi_ = nullptr; BridgePopulate bp_ = nullptr; BridgeCreate bc_ = nullptr;
    BridgeEval be_ = nullptr; BridgeRelease br_ = nullptr; BridgeShutdown bs_ = nullptr;
    bool attached_ = false, attempted_ = false, failed_ = false, first_ = true;
    unsigned w_ = 0, h_ = 0;
    int flags_ = 0;
    UINT64 evaluations_ = 0;

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
    Result PopulateGuarded(DWORD *exception) {
        __try { return bp_(populate_, params_); }
        __except(EXCEPTION_EXECUTE_HANDLER) { *exception = GetExceptionCode(); return 0xBAD00000UL; }
    }
    Result CreateGuarded(DWORD *exception) {
        __try { return bc_(create_, initList_, m3k::FeatureId, params_, &feature_); }
        __except(EXCEPTION_EXECUTE_HANDLER) { *exception = GetExceptionCode(); return 0xBAD00000UL; }
    }
    Result EvalGuarded(ID3D12GraphicsCommandList *list, DWORD *exception) {
        __try { return be_(eval_, list, feature_, params_); }
        __except(EXCEPTION_EXECUTE_HANDLER) { *exception = GetExceptionCode(); return 0xBAD00000UL; }
    }
    bool ReleaseGuarded() {
        __try {
            if (feature_) {
                Result r = br_(release_, feature_);
                if (!Report("feature 18 release", r)) return false;
                feature_ = nullptr;
                Log("M3K-A0: feature 18 released");
            }
            if (params_) {
                auto r = NVSDK_NGX_D3D12_DestroyParameters(params_);
                if (!Report("NR parameters destroy", r)) return false;
                params_ = nullptr;
            }
            if (attached_) {
                if (!Report("NR snippet shutdown (Feeder core retained)", bs_(shutdown_, device_))) return false;
                attached_ = false;
            }
            return true;
        } __except(EXCEPTION_EXECUTE_HANDLER) {
            Log("M3K-A0: cleanup exception=0x%08lX; retaining runtime until process exit", GetExceptionCode());
            return false;
        }
    }
    bool Retire() {
        if (!queue_ || !fence_) return true; // no list could have been submitted
        UINT64 value = ++fenceValue_;
        HRESULT hr = queue_->Signal(fence_, value);
        if (SUCCEEDED(hr) && fence_->GetCompletedValue() < value) {
            hr = fence_->SetEventOnCompletion(value, event_);
            if (SUCCEEDED(hr) && WaitForSingleObject(event_, 10000) != WAIT_OBJECT_0) hr = HRESULT_FROM_WIN32(WAIT_TIMEOUT);
        }
        if (FAILED(hr) || FAILED(device_->GetDeviceRemovedReason())) {
            Log("M3K-A0: GPU retirement failed hr=0x%08lX; NR bypassed, retaining resources", hr);
            failed_ = true;
            return false;
        }
        return true;
    }
    bool MakeOutput() {
        if (output_) return true;
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
            D3D12_RESOURCE_STATE_UNORDERED_ACCESS, nullptr, IID_PPV_ARGS(&output_));
        Log("M3K-A1: NR output %ux%u format=%u UAV allocation hr=0x%08lX", w_, h_, unsigned(format), hr);
        if (FAILED(hr)) return false;
        output_->SetName(L"M3K native feature 18 output");
        return true;
    }
public:
    // No implicit destructor: failed GPU retirement deliberately retains ownership.
    // Shutdown is called before Feeder releases its frame resources/core/device.
    bool ShutdownRuntime(bool dying = false) {
        if (dying && attempted_) {
            Log("M3K-A0: process teardown; runtime calls skipped, resources retained until exit");
            failed_ = true; return false;
        }
        if (!Retire() || !ReleaseGuarded()) { failed_ = true; return false; }
        Drop(output_); Drop(initList_); Drop(allocator_); Drop(fence_);
        if (event_) CloseHandle(event_);
        Drop(queue_); Drop(device_);
        if (runtime_) FreeLibrary(runtime_);
        if (bridge_) FreeLibrary(bridge_);
        *this = M3KNr{};
        return true;
    }
    bool Prepare(HMODULE owner, ID3D12Device *device, ID3D12CommandQueue *queue,
                 unsigned w, unsigned h, int flags) {
        if (attempted_ && device_ && (device_ != device || w_ != w || h_ != h || flags_ != flags)) {
            if (!ShutdownRuntime()) return false;
        }
        if (attempted_) return !failed_ && feature_ && device_ == device && w_ == w && h_ == h && flags_ == flags;
        attempted_ = true; failed_ = true; // every early return is a latched bypass
        w_ = w; h_ = h; flags_ = flags;
        wchar_t base[MAX_PATH] = {}, path[MAX_PATH] = {}, shim[MAX_PATH] = {};
        if (!GetModuleFileNameW(owner, base, MAX_PATH) || !wcsrchr(base, L'\\')) return false;
        *wcsrchr(base, L'\\') = 0;
        if (_snwprintf_s(path, _TRUNCATE, L"%s\\m3k\\nvngx_dlssnr.dll", base) < 0 ||
            _snwprintf_s(shim, _TRUNCATE, L"%s\\m3k\\m3k-nvngx.dll", base) < 0) return false;
        if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES) {
            Log("M3K-A0: DLSS NR runtime missing: %ls; DLAA bypass active", path); return false;
        }
        Log("M3K-A0: DLSS NR runtime found: %ls", path);
        // Refuse a preloaded competing NR provider; loading a second private copy
        // alongside its hooks is not a supported M3K ownership contract.
        if (GetModuleHandleW(L"nvngx_dlssnr.dll")) {
            Log("M3K-A0: NR runtime already loaded by another provider; bypass (restart without that provider)"); return false;
        }
        runtime_ = LoadLibraryExW(path, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
        if (!runtime_) { Log("M3K-A0: runtime load failed error=%lu", GetLastError()); return false; }
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
            Log("M3K-A0: required runtime/shim export missing; DLAA bypass active"); return false;
        }
        device_ = device; device_->AddRef(); queue_ = queue; queue_->AddRef();
        DWORD exception = 0;
        Result r = AttachGuarded(path, &exception);
        if (!Report("snippet Init_Ext (reuse Feeder D3D12/NGX core)", r) || exception) {
            Log("M3K-A0: attach failed exception=0x%08lX; DLAA bypass active", exception); return false;
        }
        attached_ = true;
        if (!Report("allocate separate NR parameters", NVSDK_NGX_D3D12_AllocateParameters(&params_)) || !params_) return false;
        // Populate must follow allocation/reset; it installs the private provider callbacks.
        if (!Report("PopulateParameters_Impl", PopulateGuarded(&exception)) || exception) return false;
        m3k::CreateContract(params_, w, h, flags);
        if (FAILED(device_->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator_))) ||
            FAILED(device_->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator_, nullptr, IID_PPV_ARGS(&initList_))) ||
            FAILED(device_->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence_)))) return false;
        event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (!event_) return false;
        r = CreateGuarded(&exception);
        Log("M3K-A0: feature 18 create result=0x%08lX exception=0x%08lX handle=%p; %ux%u -> %ux%u style=0 preset=1 reset=1",
            r, exception, feature_, w, h, w, h);
        // An error or exception may have left partial commands. Never submit them.
        if (!Ok(r) || exception || !feature_ || FAILED(initList_->Close())) return false;
        ID3D12CommandList *lists[] = {initList_}; queue_->ExecuteCommandLists(1, lists);
        if (!Retire()) return false;
        failed_ = false;
        Log("M3K-A0: feature 18 creation SUCCESS");
        return true;
    }
    bool Ready() const { return feature_ && !failed_; }
    void ResetHistory() { first_ = true; }
    // -1: reject this entire unsubmitted frame recording and replay baseline;
    //  0: no NR commands recorded, original DLAA input remains usable;
    //  1: output is ready as an SRV for the downstream DLAA call on this list.
    int Evaluate(ID3D12GraphicsCommandList *list, const NVSDK_NGX_D3D12_DLSS_Eval_Params &ep) {
        if (!Ready()) return 0;
        auto color = ep.Feature.pInColor, depth = ep.pInDepth, mv = ep.pInMotionVectors;
        if (!color || !depth || !mv) { failed_ = true; Log("M3K-A1: missing same-frame guide; NR bypassed"); return 0; }
        const auto cd = color->GetDesc(), dd = depth->GetDesc(), md = mv->GetDesc();
        bool valid = cd.Width == w_ && cd.Height == h_ && dd.Width == w_ && dd.Height == h_ &&
            md.Width == w_ && md.Height == h_ && dd.Format == DXGI_FORMAT_R32_FLOAT && md.Format == DXGI_FORMAT_R16G16_FLOAT &&
            cd.SampleDesc.Count == 1 && dd.SampleDesc.Count == 1 && md.SampleDesc.Count == 1 &&
            (cd.Format == DXGI_FORMAT_B8G8R8A8_UNORM || cd.Format == DXGI_FORMAT_R8G8B8A8_UNORM || cd.Format == DXGI_FORMAT_R16G16B16A16_FLOAT);
        if (!valid || !MakeOutput()) {
            failed_ = true; Log("M3K-A1: unsupported native texture contract/allocation; NR bypassed"); return 0;
        }
        const bool reset = first_ || ep.InReset;
        m3k::EvalContract(params_, color, output_, depth, mv, w_, h_, reset,
            (flags_ & NVSDK_NGX_DLSS_Feature_Flags_DepthInverted) != 0,
            ep.InJitterOffsetX, ep.InJitterOffsetY, ep.InMVScaleX, ep.InMVScaleY, ep.InPreExposure, ep.InExposureScale);
        DWORD exception = 0;
        Result r = EvalGuarded(list, &exception);
        ++evaluations_;
        if (evaluations_ == 1 || evaluations_ % 300 == 0 || !Ok(r) || exception)
            Log("M3K-A1: feature 18 evaluation %s result=0x%08lX exception=0x%08lX frame=%llu %ux%u reset=%d style=0",
                Ok(r) && !exception ? "SUCCESS" : "FAILED", r, exception, evaluations_, w_, h_, int(reset));
        if (!Ok(r) || exception) { failed_ = true; first_ = true; return -1; }
        Transition(list, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        first_ = false;
        return 1;
    }
    ID3D12Resource *Output() const { return output_; }
    void Finish(ID3D12GraphicsCommandList *list) {
        Transition(list, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    }
    void Transition(ID3D12GraphicsCommandList *list, D3D12_RESOURCE_STATES before, D3D12_RESOURCE_STATES after) {
        D3D12_RESOURCE_BARRIER b = {};
        b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION; b.Transition.pResource = output_;
        b.Transition.StateBefore = before; b.Transition.StateAfter = after;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        list->ResourceBarrier(1, &b); // transition orders the UAV writes before DLAA reads
    }
};

static M3KNr g_m3k;
