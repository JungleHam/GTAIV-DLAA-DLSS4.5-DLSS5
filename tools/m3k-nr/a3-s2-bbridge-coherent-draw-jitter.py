#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: a3-s2-bbridge-coherent-draw-jitter.py <b-bridge-root>")

root = Path(sys.argv[1])
device = root / "src" / "client" / "d3d9_device.cpp"
swap = root / "src" / "client" / "d3d9_swapchain.cpp"
for source in (device, swap):
    if not source.is_file():
        raise SystemExit(f"missing b-bridge source: {source}")

dev = device.read_text(encoding="utf-8")
swp = swap.read_text(encoding="utf-8")
if "M3K A3-S2" in dev or "M3kJitterPublishPresent" in swp:
    print("A3-S2 coherent draw jitter patch already present")
    raise SystemExit(0)

global_anchor = "extern NamedSemaphore* gpPresent;\nextern std::mutex gSwapChainMapMutex;\nextern SwapChainMap gSwapChainMap;\n"
global_new = r'''extern NamedSemaphore* gpPresent;
extern std::mutex gSwapChainMapMutex;
extern SwapChainMap gSwapChainMap;

// M3K A3-S2: coherent draw-boundary GTA IV raster jitter + cross-process handoff.
//
// A3-S1 modified whichever SetVertexShaderConstantF upload happened to overlap c8-c11.
// That works only if every draw receives all four WVP rows. GTA IV is allowed to update
// those rows partially or redundantly, which can leave the server with rows carrying
// different temporal phases. A3-S2 keeps the client's canonical D3D9 state completely
// unjittered, then immediately before every draw sends one COMPLETE c8-c11 WVP built
// from that canonical state. This mirrors the important architectural property observed
// in dxvk-remix: apply one coherent sample to the complete projection state used by the
// draw, then pass that exact pixel-space sample to NGX.
struct M3kJitterConfig {
  bool enabled = false;
  uint32_t width = 0;
  uint32_t height = 0;
};

#pragma pack(push, 4)
struct M3kJitterSharedV1 {
  uint32_t magic;
  uint32_t version;
  volatile LONG writeSeq;
  LONG active;
  LONG frame;
  LONG epoch;
  LONG renderWidth;
  LONG renderHeight;
  float jitterX;
  float jitterY;
};
#pragma pack(pop)

static constexpr uint32_t kM3kJitterMagic = 0x314A334Du; // "M3J1"
static constexpr uint32_t kM3kJitterVersion = 1u;
static constexpr uint32_t kM3kJitterPhases = 16u; // Hold sequence fixed while isolating A3-S2 raster coherence.

static M3kJitterConfig g_m3kJitterConfig;
static bool g_m3kJitterConfigFirst = true;
static ULONGLONG g_m3kJitterNextPoll = 0;
static uint32_t g_m3kJitterPhase = 0;
static float g_m3kJitterX = 0.0f, g_m3kJitterY = 0.0f;
static bool g_m3kJitterTouchedThisFrame = false;
// True only when our last synthetic full-WVP send actually shifted server c8-c11.
// Keep this true across an INI disable transition so the next real draw restores the
// server to the unjittered canonical WVP before rendering.
static bool g_m3kServerWvpShifted = false;
static LONG g_m3kJitterFrame = 0;
static LONG g_m3kJitterEpoch = 1;
static HANDLE g_m3kJitterMap = nullptr;
static M3kJitterSharedV1* g_m3kJitterShared = nullptr;

static bool M3kJitterConfigPath(wchar_t* path, size_t pathCount) {
  DWORD length = GetModuleFileNameW(nullptr, path, DWORD(pathCount));
  if (!length || length >= pathCount)
    return false;
  wchar_t* slash = wcsrchr(path, L'\\');
  if (!slash)
    return false;
  static const wchar_t suffix[] = L".trex\\m3k-nr.ini";
  const size_t prefix = size_t(slash + 1 - path);
  if (prefix + (sizeof(suffix) / sizeof(suffix[0])) > pathCount)
    return false;
  lstrcpyW(slash + 1, suffix);
  return true;
}

static float M3kHalton(uint32_t index, uint32_t base) {
  float result = 0.0f;
  float inv = 1.0f / static_cast<float>(base);
  float f = inv;
  while (index) {
    result += f * static_cast<float>(index % base);
    index /= base;
    f *= inv;
  }
  return result;
}

static void M3kJitterSetPhase(uint32_t phase) {
  g_m3kJitterPhase = phase % kM3kJitterPhases;
  if (g_m3kJitterPhase == 0) {
    g_m3kJitterX = 0.0f;
    g_m3kJitterY = 0.0f;
  } else {
    g_m3kJitterX = M3kHalton(g_m3kJitterPhase, 2u) - 0.5f;
    g_m3kJitterY = M3kHalton(g_m3kJitterPhase, 3u) - 0.5f;
  }
}

static M3kJitterConfig M3kGetJitterConfig() {
  const ULONGLONG now = GetTickCount64();
  if (now < g_m3kJitterNextPoll)
    return g_m3kJitterConfig;
  g_m3kJitterNextPoll = now + 250;

  M3kJitterConfig next;
  wchar_t path[MAX_PATH] = { };
  if (M3kJitterConfigPath(path, MAX_PATH)) {
    next.enabled = GetPrivateProfileIntW(L"M3K", L"TemporalJitter", 0, path) != 0;
    next.width = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
    next.height = GetPrivateProfileIntW(L"M3K", L"RenderHeight", 0, path);
  }
  const bool changed = next.enabled != g_m3kJitterConfig.enabled ||
                       next.width != g_m3kJitterConfig.width ||
                       next.height != g_m3kJitterConfig.height;
  if (g_m3kJitterConfigFirst || changed) {
    g_m3kJitterConfig = next;
    M3kJitterSetPhase(0);
    g_m3kJitterTouchedThisFrame = false;
    if (!g_m3kJitterConfigFirst)
      InterlockedIncrement(&g_m3kJitterEpoch);
    Logger::info(format_string("[M3K-JITTER] A3-S2 config enabled=%d render=%ux%u epoch=%ld",
      next.enabled ? 1 : 0, next.width, next.height, g_m3kJitterEpoch));
    g_m3kJitterConfigFirst = false;
  } else {
    g_m3kJitterConfig = next;
  }
  return g_m3kJitterConfig;
}

static bool M3kWvpProjective(const float* m) {
  // A3-S0 hardware proof: real scene WVP blocks have a projective W column, while
  // the dominant affine/UI family has w=(0,0,0,1).
  const float wxyz = fabsf(m[3]) + fabsf(m[7]) + fabsf(m[11]);
  return wxyz > 0.02f && fabsf(m[15] - 1.0f) > 0.001f;
}

static bool M3kBuildDrawWvp(const M3kJitterConfig& config,
                            const float* originalWvp,
                            UINT viewportWidth, UINT viewportHeight,
                            float* desiredWvp) {
  memcpy(desiredWvp, originalWvp, 16u * sizeof(float));
  if (!config.enabled || !config.width || !config.height ||
      viewportWidth != config.width || viewportHeight != config.height ||
      !M3kWvpProjective(originalWvp))
    return false;

  const float ndcX = 2.0f * g_m3kJitterX / static_cast<float>(config.width);
  const float ndcY = -2.0f * g_m3kJitterY / static_cast<float>(config.height);
  for (UINT row = 0; row < 4u; ++row) {
    const size_t i = size_t(row) * 4u;
    const float w = desiredWvp[i + 3u];
    desiredWvp[i + 0u] += ndcX * w;
    desiredWvp[i + 1u] += ndcY * w;
  }
  return true;
}

// This macro intentionally expands inside Direct3DDevice9Ex_LSS member functions:
// it must use the device's canonical m_state and its existing state-batch path. Any
// non-batched Draw command flushes a pending state batch before reaching the server,
// so the synthetic c8-c11 update is ordered immediately before the draw.
#define M3K_SYNC_WVP_FOR_DRAW() \
  do { \
    const M3kJitterConfig m3kCfg = M3kGetJitterConfig(); \
    float m3kOriginalWvp[16] = { }; \
    UINT m3kViewportW = 0, m3kViewportH = 0; \
    uint32_t m3kShaderId = 0; \
    bool m3kRecording = false; \
    { \
      BRIDGE_DEVICE_LOCKGUARD(); \
      m3kRecording = m_stateRecording != nullptr; \
      m3kViewportW = m_state.viewport.Width; \
      m3kViewportH = m_state.viewport.Height; \
      for (UINT m3kR = 0; m3kR < 4u; ++m3kR) \
        for (UINT m3kC = 0; m3kC < 4u; ++m3kC) \
          m3kOriginalWvp[m3kR * 4u + m3kC] = m_state.vertexConstants.fConsts[8u + m3kR].data[m3kC]; \
      if (auto* m3kVs = bridge_cast<Direct3DVertexShader9_LSS*>(*m_state.vertexShader)) \
        m3kShaderId = static_cast<uint32_t>(m3kVs->getId()); \
    } \
    if (!m3kRecording) { \
      float m3kDesiredWvp[16] = { }; \
      const bool m3kEligible = M3kBuildDrawWvp(m3kCfg, m3kOriginalWvp, m3kViewportW, m3kViewportH, m3kDesiredWvp); \
      const bool m3kRestore = !m3kEligible && g_m3kServerWvpShifted; \
      if (m3kEligible || m3kRestore) { \
        if (m3kRestore) memcpy(m3kDesiredWvp, m3kOriginalWvp, sizeof(m3kDesiredWvp)); \
        UID m3kConstUID = 0; \
        bool m3kBatched = false; \
        { \
          BRIDGE_DEVICE_LOCKGUARD(); \
          if (batchActive()) { \
            batchConst(Commands::IDirect3DDevice9Ex_SetVertexShaderConstantF, 8u, 4u, m3kDesiredWvp); \
            m3kBatched = true; \
          } \
        } \
        if (!m3kBatched) { \
          SetShaderConst(SetVertexShaderConstantF, 8u, m3kDesiredWvp, 4u, 16u * sizeof(float), m3kConstUID); \
          WAIT_FOR_OPTIONAL_SERVER_RESPONSE("M3K A3-S2 WVP sync", D3DERR_INVALIDCALL, m3kConstUID); \
        } \
        if (m3kEligible) { \
          g_m3kJitterTouchedThisFrame = true; \
          g_m3kServerWvpShifted = fabsf(g_m3kJitterX) + fabsf(g_m3kJitterY) > 0.000001f; \
          static uint64_t m3kDrawJitters = 0; \
          ++m3kDrawJitters; \
          if (m3kDrawJitters <= 8u || (m3kDrawJitters % 120000u) == 0u) \
            Logger::info(format_string("[M3K-JITTER2] DRAW shader=%u viewport=%ux%u phase=%u px=(%+.4f,%+.4f) full=c8+4", \
              m3kShaderId, m3kViewportW, m3kViewportH, g_m3kJitterPhase, g_m3kJitterX, g_m3kJitterY)); \
        } else { \
          g_m3kServerWvpShifted = false; \
          static uint64_t m3kDrawRestores = 0; \
          ++m3kDrawRestores; \
          if (m3kDrawRestores <= 4u || (m3kDrawRestores % 60000u) == 0u) \
            Logger::info(format_string("[M3K-JITTER2] RESTORE shader=%u viewport=%ux%u full=c8+4", \
              m3kShaderId, m3kViewportW, m3kViewportH)); \
        } \
      } \
    } \
  } while (0)

static bool M3kEnsureJitterMapping() {
  if (g_m3kJitterShared)
    return true;
  g_m3kJitterMap = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                      sizeof(M3kJitterSharedV1), L"Local\\M3K_GTAIV_Jitter_v1");
  if (!g_m3kJitterMap) {
    static bool said = false;
    if (!said) {
      said = true;
      Logger::warn(format_string("[M3K-JITTER] CreateFileMapping failed error=%lu", GetLastError()));
    }
    return false;
  }
  const bool fresh = GetLastError() != ERROR_ALREADY_EXISTS;
  g_m3kJitterShared = reinterpret_cast<M3kJitterSharedV1*>(
    MapViewOfFile(g_m3kJitterMap, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(M3kJitterSharedV1)));
  if (!g_m3kJitterShared) {
    CloseHandle(g_m3kJitterMap);
    g_m3kJitterMap = nullptr;
    return false;
  }
  if (fresh) {
    memset(g_m3kJitterShared, 0, sizeof(*g_m3kJitterShared));
    g_m3kJitterShared->magic = kM3kJitterMagic;
    g_m3kJitterShared->version = kM3kJitterVersion;
  }
  Logger::info("[M3K-JITTER] A3-S2 shared handoff ready: Local\\M3K_GTAIV_Jitter_v1");
  return true;
}

void M3kJitterPublishPresent() {
  const M3kJitterConfig config = M3kGetJitterConfig();
  const bool active = config.enabled && config.width && config.height && g_m3kJitterTouchedThisFrame;
  if (!M3kEnsureJitterMapping())
    return;

  M3kJitterSharedV1* s = g_m3kJitterShared;
  InterlockedIncrement(&s->writeSeq);
  MemoryBarrier();
  s->magic = kM3kJitterMagic;
  s->version = kM3kJitterVersion;
  s->active = active ? 1 : 0;
  s->frame = InterlockedIncrement(&g_m3kJitterFrame);
  s->epoch = g_m3kJitterEpoch;
  s->renderWidth = static_cast<LONG>(config.width);
  s->renderHeight = static_cast<LONG>(config.height);
  s->jitterX = active ? g_m3kJitterX : 0.0f;
  s->jitterY = active ? g_m3kJitterY : 0.0f;
  MemoryBarrier();
  InterlockedIncrement(&s->writeSeq);

  const LONG frame = s->frame;
  if (active && (frame <= 4 || (frame % 300) == 0))
    Logger::info(format_string("[M3K-JITTER] A3-S2 publish frame=%ld epoch=%ld phase=%u px=(%+.4f,%+.4f) render=%ux%u",
      frame, g_m3kJitterEpoch, g_m3kJitterPhase, g_m3kJitterX, g_m3kJitterY,
      config.width, config.height));
}

void M3kJitterAdvanceAfterPresent() {
  const M3kJitterConfig config = g_m3kJitterConfig;
  if (config.enabled && g_m3kJitterTouchedThisFrame)
    M3kJitterSetPhase(g_m3kJitterPhase + 1u);
  else
    M3kJitterSetPhase(0);
  g_m3kJitterTouchedThisFrame = false;
}
'''
if dev.count(global_anchor) != 1:
    raise SystemExit(f"device global anchor count={dev.count(global_anchor)}, expected 1")
dev = dev.replace(global_anchor, global_new, 1)

# Inject the coherent full-WVP sync immediately before each D3D9 draw path. Keep the
# normal SetVertexShaderConstantF implementation untouched so m_state always remains
# the canonical, unjittered GTA IV state.
draw_signatures = (
    "HRESULT Direct3DDevice9Ex_LSS<EnableSync>::DrawPrimitive(D3DPRIMITIVETYPE PrimitiveType, UINT StartVertex, UINT PrimitiveCount) {",
    "HRESULT Direct3DDevice9Ex_LSS<EnableSync>::DrawIndexedPrimitive(D3DPRIMITIVETYPE Type, INT BaseVertexIndex, UINT MinVertexIndex, UINT NumVertices, UINT startIndex, UINT primCount) {",
    "HRESULT Direct3DDevice9Ex_LSS<EnableSync>::DrawPrimitiveUP(D3DPRIMITIVETYPE PrimitiveType, UINT PrimitiveCount, CONST void* pVertexStreamZeroData, UINT VertexStreamZeroStride) {",
    "HRESULT Direct3DDevice9Ex_LSS<EnableSync>::DrawIndexedPrimitiveUP(D3DPRIMITIVETYPE PrimitiveType, UINT MinIndex, UINT NumVertices, UINT PrimitiveCount, CONST void* pIndexData, D3DFORMAT IndexDataFormat, CONST void* pVertexStreamZeroData, UINT VertexStreamZeroStride) {",
)
for signature in draw_signatures:
    start = dev.find(signature)
    if start < 0:
        raise SystemExit(f"missing draw signature: {signature}")
    log_pos = dev.find("  LogFunctionCall();\n", start)
    if log_pos < 0 or log_pos > start + 1200:
        raise SystemExit(f"missing LogFunctionCall near draw signature: {signature}")
    insert_at = log_pos + len("  LogFunctionCall();\n")
    if dev.startswith("  M3K_SYNC_WVP_FOR_DRAW();\n", insert_at):
        continue
    dev = dev[:insert_at] + "  M3K_SYNC_WVP_FOR_DRAW();\n" + dev[insert_at:]

if dev.count("M3K_SYNC_WVP_FOR_DRAW();") != 4:
    raise SystemExit(f"draw sync insertion count={dev.count('M3K_SYNC_WVP_FOR_DRAW();')}, expected 4")

present_anchor = '''  // Send present first\n  {\n    ClientMessage c(Commands::IDirect3DSwapChain9_Present, getId());\n'''
present_new = '''  // Publish the exact jitter used by the just-finished D3D9 frame before the\n  // Present command reaches the 64-bit server/Feeder.\n  extern void M3kJitterPublishPresent();\n  M3kJitterPublishPresent();\n\n  // Send present first\n  {\n    ClientMessage c(Commands::IDirect3DSwapChain9_Present, getId());\n'''
if swp.count(present_anchor) != 1:
    raise SystemExit(f"Present publish anchor count={swp.count(present_anchor)}, expected 1")
swp = swp.replace(present_anchor, present_new, 1)

advance_anchor = '''  // End of frame: hand the server everything batched so far (and before any Present-semaphore wait).\n  flushAllBridgeWriters();\n\n  extern HRESULT syncOnPresent();\n'''
advance_new = '''  // End of frame: hand the server everything batched so far (and before any Present-semaphore wait).\n  flushAllBridgeWriters();\n\n  // The shared snapshot stays unchanged for the server; only the local next-frame\n  // phase advances here. syncOnPresent prevents publishing another frame first.\n  extern void M3kJitterAdvanceAfterPresent();\n  M3kJitterAdvanceAfterPresent();\n\n  extern HRESULT syncOnPresent();\n'''
if swp.count(advance_anchor) != 1:
    raise SystemExit(f"Present advance anchor count={swp.count(advance_anchor)}, expected 1")
swp = swp.replace(advance_anchor, advance_new, 1)

for marker in (
    "M3K A3-S2: coherent draw-boundary",
    "M3K_SYNC_WVP_FOR_DRAW",
    "[M3K-JITTER2] DRAW",
    "[M3K-JITTER2] RESTORE",
    "M3K_GTAIV_Jitter_v1",
    "M3kJitterPublishPresent",
    "M3kJitterAdvanceAfterPresent",
):
    if marker not in dev and marker not in swp:
        raise SystemExit(f"verification failed: {marker}")

# A3-S2's central invariant: upload-time jitter from A3-S1 must not exist here.
if "M3kApplyJitterToUpload" in dev or "Redundant game constants still need forwarding" in dev:
    raise SystemExit("A3-S1 upload-time jitter unexpectedly present in A3-S2 source")

device.write_text(dev, encoding="utf-8", newline="\n")
swap.write_text(swp, encoding="utf-8", newline="\n")
print(f"A3-S2 coherent draw-boundary jitter patch applied: {device} + {swap}")
