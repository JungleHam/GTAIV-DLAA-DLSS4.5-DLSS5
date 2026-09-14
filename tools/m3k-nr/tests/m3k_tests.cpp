// SPDX-License-Identifier: MIT
// CPU tests: no NVIDIA runtime, D3D12 device, game, or GPU work is created.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d12.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <intrin.h>
#include <map>
#include <string>
#include <variant>
#include <nvsdk_ngx.h>
#include <nvsdk_ngx_helpers.h>
#include "../src/m3k_contract.h"

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
using Value = std::variant<unsigned, int, float, ID3D12Resource *>;
struct RecordedParams {
    std::map<std::string, Value> values;
    template<class T> void Set(const char *name, T v) { values[name] = v; }
    template<class T> T Get(const char *name) const { return std::get<T>(values.at(name)); }
};
static ID3D12Resource *Ptr(size_t n) { return reinterpret_cast<ID3D12Resource *>(n); }
static void ContractTest() {
    static_assert(NVSDK_NGX_PerfQuality_Value_DLAA == 5);
    RecordedParams p;
    m3k::CreateContract(&p, 2560, 1440, 9);
    CHECK(p.Get<unsigned>("Width") == 2560 && p.Get<unsigned>("OutWidth") == 2560);
    CHECK(p.Get<unsigned>("Height") == 1440 && p.Get<unsigned>("OutHeight") == 1440);
    CHECK(p.Get<float>("DLSSNR.ScalingRatio") == 1.0f);
    CHECK(p.Get<unsigned>("DLSSNR.Style") == 0);
    CHECK(p.Get<int>("PerfQualityValue") == NVSDK_NGX_PerfQuality_Value_DLAA);
    CHECK(p.Get<int>("DLSS.Feature.Create.Flags") == 9);
    m3k::EvalContract(&p, Ptr(1), Ptr(2), Ptr(3), Ptr(4), 2560, 1440, true, false,
        0.25f, -0.125f, -2560.0f, 1440.0f, 1.25f, 0.75f);
    CHECK(p.Get<ID3D12Resource *>("Color") == Ptr(1));
    CHECK(p.Get<ID3D12Resource *>("DLSSNR.Output") == Ptr(2));
    CHECK(p.Get<ID3D12Resource *>("Depth") == p.Get<ID3D12Resource *>("DLSSNR.Depth"));
    CHECK(p.Get<ID3D12Resource *>("MotionVectors") == p.Get<ID3D12Resource *>("DLSSNR.MVec"));
    CHECK(p.Get<int>("DLSSNR.ColorSubrectWidth") == 2560);
    CHECK(p.Get<int>("DLSSNR.OutputSubrectHeight") == 1440);
    CHECK(p.Get<int>("DLSSNR.Reset") == 1 && p.Get<int>("Reset") == 1);
    CHECK(p.Get<float>("Jitter.Offset.X") == p.Get<float>("DLSSNR.JitterOffsetX"));
    CHECK(p.Get<float>("DLSSNR.JitterOffsetY") == -0.125f);
    CHECK(p.Get<float>("DLSSNR.MVecScaleX") == -2560.0f);
    CHECK(p.Get<float>("DLSSNR.MVecScaleY") == 1440.0f);
    CHECK(p.Get<float>("DLSS.Pre.Exposure") == 1.25f);
    CHECK(p.Get<unsigned>("DLSSNR.DepthInverted") == 0);
    CHECK(p.Get<ID3D12Resource *>("DLSSNR.UI") == nullptr);
    CHECK(p.Get<ID3D12Resource *>("DLSSNR.ControlMask") == nullptr);
    m3k::EvalContract(&p, Ptr(5), Ptr(2), Ptr(6), Ptr(7), 2560, 1440, false, true, 0.f, 0.f, 1.f, 1.f, 1.f, 1.f);
    CHECK(p.Get<ID3D12Resource *>("Color") == Ptr(5)); // next-frame pointers replace old values
    CHECK(p.Get<int>("Reset") == 0 && p.Get<int>("DLSSNR.Reset") == 0);
    CHECK(p.Get<unsigned>("DLSSNR.DepthInverted") == 1);
    puts("PASS native 2560x1440 typed contract, same-frame guides, history/reset, no UI mask");
}

// Compile the real chain adapter against a fake NR provider/recording host. This
// exercises failure recovery, not the NVIDIA runtime or the moved input commands.
static void Log(const char *, ...) {}
static int aborts, begins, inputs, srCalls, finishes, historyResets, evalCalls;
static bool beginOk = true;
static NVSDK_NGX_Result srResult = NVSDK_NGX_Result_Success;
static DWORD srException = 0;
static NVSDK_NGX_D3D12_DLSS_Eval_Params observed;
static void AbortCommands() { ++aborts; }
static bool BeginCommands() { ++begins; return beginOk; }
static void M3kRecordVkInputs() { ++inputs; }
static NVSDK_NGX_Result SafeEvaluateDLSS(NVSDK_NGX_D3D12_DLSS_Eval_Params *ep, DWORD *code) {
    ++srCalls; observed = *ep; *code = srException; return srResult;
}
struct FakeTexture { D3D12_RESOURCE_DESC GetDesc() { D3D12_RESOURCE_DESC d = {}; d.Width = 2560; d.Height = 1440; return d; } };
struct FakeFeed {
    bool ngx_inited = true, sr_active = false;
    void *feature = nullptr;
    FakeTexture *tex12[1] = {};
    ID3D12Device *dev12 = nullptr;
    ID3D12CommandQueue *queue = nullptr;
    ID3D12GraphicsCommandList *list = nullptr;
    unsigned width = 2560, height = 1440;
    int create_flags = 0;
} g;
struct { int mode = 2, passthrough = 0, work_resolution = 100; } g_cfg;
static HMODULE g_self;
static bool g_ngx_dying;
static constexpr int SLOT_OUTPUT = 0;
struct FakeNR {
    int result = 0;
    int prepares = 0, shutdowns = 0;
    bool Prepare(HMODULE, ID3D12Device *, ID3D12CommandQueue *, unsigned, unsigned, int) { ++prepares; return true; }
    bool ShutdownRuntime(bool = false) { ++shutdowns; return true; }
    void ResetHistory() { ++historyResets; }
    int Evaluate(ID3D12GraphicsCommandList *, const NVSDK_NGX_D3D12_DLSS_Eval_Params &) { ++evalCalls; return result; }
    ID3D12Resource *Output() { return Ptr(99); }
    void Finish(ID3D12GraphicsCommandList *) { ++finishes; }
} g_m3k;
static ULONGLONG fakeTime = 1001;
static UINT requestedMode = 0;
static ULONGLONG TestClock() { return fakeTime; }
static UINT TestMode(LPCWSTR section, LPCWSTR key, INT fallback, LPCWSTR path) {
    CHECK(wcscmp(section, L"M3K") == 0 && wcscmp(key, L"Mode") == 0 && fallback == 0);
    CHECK(wcsstr(path, L"m3k-nr.ini")); return requestedMode;
}
#define GetTickCount64 TestClock
#define GetPrivateProfileIntW TestMode
#include "../src/m3k_vk.h"
#undef GetTickCount64
#undef GetPrivateProfileIntW

static void ModeTest() {
    FakeTexture texture; g.tex12[0] = &texture; g.feature = Ptr(10);
    M3kPrepareFrame();
    CHECK(g_m3kMode == 0 && !g_m3kArmed && g_m3k.prepares == 0);
    requestedMode = 1; fakeTime += 1001;
    M3kPrepareFrame(); CHECK(g_m3kMode == 1 && g_m3kArmed && g_m3k.prepares == 1);
    requestedMode = 2; fakeTime += 1001;
    M3kPrepareFrame(); CHECK(g_m3kMode == 2 && g_m3kArmed && g_m3k.prepares == 2);
    requestedMode = 0;
    M3kPrepareFrame(); CHECK(g_m3kMode == 2); // wait for the once-per-second poll
    fakeTime += 1001;
    M3kPrepareFrame(); CHECK(!g_m3kArmed && g_m3kMode == 0 && g_m3k.shutdowns == 2);
    requestedMode = UINT(-1); fakeTime += 1001;
    M3kPrepareFrame(); CHECK(!g_m3kArmed && g_m3kMode == 0);
    requestedMode = 2; fakeTime += 1001; g_cfg.work_resolution = 50;
    const int previous = g_m3k.prepares;
    M3kPrepareFrame(); CHECK(!g_m3kArmed && g_m3k.prepares == previous);
    g_cfg.work_resolution = 100; g_cfg.passthrough = 1;
    M3kPrepareFrame(); CHECK(!g_m3kArmed && g_m3k.prepares == previous);
    g_cfg.passthrough = 0; g_m3kWasUsed = false;
    puts("PASS mode polling, default-off initialization, create-only arming, invalid mode and non-native bypass");
}

static void ChainTest() {
    NVSDK_NGX_D3D12_DLSS_Eval_Params ep = {};
    ep.Feature.pInColor = Ptr(1); ep.Feature.pInOutput = Ptr(2);
    ep.pInDepth = Ptr(3); ep.pInMotionVectors = Ptr(4); ep.pInBiasCurrentColorMask = Ptr(5);
    ep.InJitterOffsetX = .25f; ep.InMVScaleX = -2560.f;
    ep.InRenderSubrectDimensions.Width = 2560; ep.InRenderSubrectDimensions.Height = 1440;
    const auto original = ep;
    DWORD code = 0;
    for (int mode : {0, 1}) {
        g_m3kMode = mode; g_m3kArmed = true;
        CHECK(NVSDK_NGX_SUCCEED(M3kEvaluateBeforeDlaa(&ep, &code)));
        CHECK(memcmp(&observed, &original, sizeof(ep)) == 0);
        CHECK(evalCalls == 0 && aborts == 0 && finishes == 0);
    }
    g_m3kMode = 2; g_m3k.result = 1;
    M3kEvaluateBeforeDlaa(&ep, &code);
    auto expected = ep; expected.Feature.pInColor = Ptr(99); expected.InReset = 1;
    CHECK(memcmp(&observed, &expected, sizeof(ep)) == 0);
    CHECK(memcmp(&ep, &original, sizeof(ep)) == 0); // caller's input is immutable
    M3kEvaluateBeforeDlaa(&ep, &code);
    CHECK(observed.InReset == 0 && observed.Feature.pInColor == Ptr(99));
    g_m3kMode = 0;
    M3kEvaluateBeforeDlaa(&ep, &code);
    CHECK(observed.InReset == 1 && observed.Feature.pInColor == Ptr(1));
    g_m3kMode = 2; g_m3k.result = -1;
    M3kEvaluateBeforeDlaa(&ep, &code);
    CHECK(aborts == 1 && begins == 1 && inputs == 1);
    expected = ep; expected.InReset = 1;
    CHECK(memcmp(&observed, &expected, sizeof(ep)) == 0); // same-frame baseline replay
    const int before = srCalls;
    beginOk = false;
    CHECK(NVSDK_NGX_FAILED(M3kEvaluateBeforeDlaa(&ep, &code)));
    CHECK(code != 0 && srCalls == before && inputs == 1);
    beginOk = true; code = 0; g_m3k.result = 1; srException = 0xc0000005;
    const int oldFinish = finishes;
    M3kEvaluateBeforeDlaa(&ep, &code);
    CHECK(code == srException && finishes == oldFinish && historyResets > 0 && !g_m3kWasUsed);
    puts("PASS default/A0 image-contract bypass, A/B reset, NR failure replay, failed recovery, SR exception");
}

using R = unsigned long;
static int shimCalls;
static void Caller(void *address) {
    HMODULE m = nullptr; wchar_t name[MAX_PATH] = {};
    CHECK(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(address), &m));
    CHECK(GetModuleFileNameW(m, name, MAX_PATH));
    CHECK(wcsstr(name, L"m3k-nvngx.dll") != nullptr);
    ++shimCalls;
}
static __declspec(noinline) R __cdecl TestInit(unsigned long long id, const wchar_t *path, ID3D12Device *, unsigned long v, const void *info) {
    Caller(_ReturnAddress()); CHECK(id == m3k::SnippetAppId && v == NVSDK_NGX_Version_API && !info && wcscmp(path, L"test") == 0); return 1;
}
static __declspec(noinline) R __cdecl TestPopulate(void *params) { Caller(_ReturnAddress()); CHECK(params == Ptr(8)); return 1; }
static __declspec(noinline) R __cdecl TestCreate(ID3D12GraphicsCommandList *, int id, void *params, void **handle) {
    Caller(_ReturnAddress()); CHECK(id == 18 && params == Ptr(8)); *handle = Ptr(9); return 1;
}
static __declspec(noinline) R __cdecl TestEval(ID3D12GraphicsCommandList *, const void *h, const void *p, void *cb) {
    Caller(_ReturnAddress()); CHECK(h == Ptr(9) && p == Ptr(8) && !cb); return 0xBAD00005UL;
}
static __declspec(noinline) R __cdecl TestRelease(void *h) { Caller(_ReturnAddress()); CHECK(h == Ptr(9)); return 1; }
static __declspec(noinline) R __cdecl TestShutdown(ID3D12Device *d) { Caller(_ReturnAddress()); CHECK(!d); return 1; }
template<class T> static T Proc(HMODULE m, const char *name) { auto p = GetProcAddress(m, name); CHECK(p); return reinterpret_cast<T>(p); }
static void ShimTest(const char *path) {
    HMODULE m = LoadLibraryA(path); CHECK(m);
    auto init = Proc<R (__cdecl *)(decltype(&TestInit), unsigned long long, const wchar_t *, ID3D12Device *, unsigned long)>(m, "M3K_Init");
    auto pop = Proc<R (__cdecl *)(decltype(&TestPopulate), void *)>(m, "M3K_Populate");
    auto create = Proc<R (__cdecl *)(decltype(&TestCreate), ID3D12GraphicsCommandList *, int, void *, void **)>(m, "M3K_Create");
    auto eval = Proc<R (__cdecl *)(decltype(&TestEval), ID3D12GraphicsCommandList *, const void *, const void *)>(m, "M3K_Evaluate");
    auto release = Proc<R (__cdecl *)(decltype(&TestRelease), void *)>(m, "M3K_Release");
    auto shutdown = Proc<R (__cdecl *)(decltype(&TestShutdown), ID3D12Device *)>(m, "M3K_Shutdown");
    CHECK(init(nullptr, 0, nullptr, nullptr, 0) == 0xBAD00005UL);
    CHECK(init(TestInit, m3k::SnippetAppId, L"test", nullptr, NVSDK_NGX_Version_API) == 1);
    CHECK(pop(TestPopulate, Ptr(8)) == 1);
    void *handle = nullptr;
    CHECK(create(TestCreate, nullptr, 18, Ptr(8), &handle) == 1 && handle == Ptr(9));
    CHECK(eval(TestEval, nullptr, handle, Ptr(8)) == 0xBAD00005UL);
    CHECK(release(TestRelease, handle) == 1 && shutdown(TestShutdown, nullptr) == 1);
    CHECK(shimCalls == 6);
    FreeLibrary(m);
    puts("PASS x64 shim exports, ABI forwarding, error propagation, actual return-address module");
}
int main(int argc, char **argv) {
    CHECK(argc == 2);
    ContractTest(); ModeTest(); ChainTest(); ShimTest(argv[1]);
    puts("M3K CPU tests passed; NVIDIA feature 18 / GTA hardware path NOT tested.");
}
