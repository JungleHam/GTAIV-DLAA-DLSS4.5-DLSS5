#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: a3-s1-bbridge-temporal-jitter.py <b-bridge-root>")

root = Path(sys.argv[1])
device = root / "src" / "client" / "d3d9_device.cpp"
swap = root / "src" / "client" / "d3d9_swapchain.cpp"
for source in (device, swap):
    if not source.is_file():
        raise SystemExit(f"missing b-bridge source: {source}")

dev = device.read_text(encoding="utf-8")
swp = swap.read_text(encoding="utf-8")
if "[M3K-JITTER]" in dev or "M3kJitterPublishPresent" in swp:
    print("A3-S1 temporal jitter patch already present")
    raise SystemExit(0)

global_anchor = "extern NamedSemaphore* gpPresent;\nextern std::mutex gSwapChainMapMutex;\nextern SwapChainMap gSwapChainMap;\n"
global_new = r'''extern NamedSemaphore* gpPresent;
extern std::mutex gSwapChainMapMutex;
extern SwapChainMap gSwapChainMap;

// M3K A3-S1: real GTA IV raster jitter + cross-process handoff to the 64-bit
// Feeder. One Halton sample is used for the whole D3D9 frame. Eligible projective
// c8-c11 WorldViewProjection uploads get the clip-space shift, then Present
// publishes that exact pixel-space sample before the server sees the Present.
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
static constexpr uint32_t kM3kJitterPhases = 16u; // A3-S1 functional gate; tune later.

static M3kJitterConfig g_m3kJitterConfig;
static bool g_m3kJitterConfigFirst = true;
static ULONGLONG g_m3kJitterNextPoll = 0;
static uint32_t g_m3kJitterPhase = 0;
static float g_m3kJitterX = 0.0f, g_m3kJitterY = 0.0f;
static bool g_m3kJitterTouchedThisFrame = false;
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
    Logger::info(format_string("[M3K-JITTER] config enabled=%d render=%ux%u epoch=%ld",
      next.enabled ? 1 : 0, next.width, next.height, g_m3kJitterEpoch));
    g_m3kJitterConfigFirst = false;
  } else {
    g_m3kJitterConfig = next;
  }
  return g_m3kJitterConfig;
}

static bool M3kWvpProjective(const float* m) {
  // A3-S0 hardware scan: true scene WVP c8-c11 blocks have a projective W column;
  // the huge affine/UI false-positive family has w=(0,0,0,1).
  const float wxyz = fabsf(m[3]) + fabsf(m[7]) + fabsf(m[11]);
  return wxyz > 0.02f && fabsf(m[15] - 1.0f) > 0.001f;
}

static bool M3kApplyJitterToUpload(UINT startRegister, UINT vectorCount,
                                   const float* originalWvp,
                                   UINT viewportWidth, UINT viewportHeight,
                                   bool stateBlockRecording,
                                   std::vector<float>& modified,
                                   const float* input) {
  const M3kJitterConfig config = M3kGetJitterConfig();
  if (!config.enabled || !config.width || !config.height || stateBlockRecording ||
      viewportWidth != config.width || viewportHeight != config.height ||
      !originalWvp || !M3kWvpProjective(originalWvp))
    return false;

  const UINT endRegister = startRegister + vectorCount;
  if (endRegister <= 8u || startRegister >= 12u)
    return false;

  modified.assign(input, input + size_t(vectorCount) * 4u);
  const float ndcX = 2.0f * g_m3kJitterX / static_cast<float>(config.width);
  const float ndcY = -2.0f * g_m3kJitterY / static_cast<float>(config.height);
  const UINT first = startRegister < 8u ? 8u : startRegister;
  const UINT last = endRegister > 12u ? 12u : endRegister;
  for (UINT reg = first; reg < last; ++reg) {
    const size_t i = size_t(reg - startRegister) * 4u;
    const float w = modified[i + 3u];
    modified[i + 0u] += ndcX * w;
    modified[i + 1u] += ndcY * w;
  }
  g_m3kJitterTouchedThisFrame = true;
  return true;
}

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
  Logger::info("[M3K-JITTER] shared handoff ready: Local\\M3K_GTAIV_Jitter_v1");
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
    Logger::info(format_string("[M3K-JITTER] publish frame=%ld epoch=%ld phase=%u px=(%+.4f,%+.4f) render=%ux%u",
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

old_func = r'''template<bool EnableSync>
HRESULT Direct3DDevice9Ex_LSS<EnableSync>::SetVertexShaderConstantF(UINT StartRegister, CONST float* pConstantData, UINT Vector4fCount) {
  ZoneScoped;
  LogFunctionCall();

  if (pConstantData == nullptr) {
    return D3DERR_INVALIDCALL;
  }

  HRESULT hresult = D3DERR_INVALIDCALL;
  {
    BRIDGE_DEVICE_LOCKGUARD();
    hresult =
      setShaderConstants<
      ShaderType::Vertex,
      ConstantType::Float>(
        StartRegister,
        pConstantData,
        Vector4fCount);
  }
  if (hresult == S_FALSE) {
    return S_OK;
  }
  if (SUCCEEDED(hresult)) {
    UID currentUID = 0;
    bool batched = false;
    {
      BRIDGE_DEVICE_LOCKGUARD();
      if (batchActive()) { batchConst(Commands::IDirect3DDevice9Ex_SetVertexShaderConstantF, StartRegister, Vector4fCount, pConstantData); batched = true; }
    }
    if (!batched) {
      SetShaderConst(SetVertexShaderConstantF,
                     StartRegister,
                     pConstantData,
                     Vector4fCount,
                     Vector4fCount * 4 * sizeof(float), currentUID);
      WAIT_FOR_OPTIONAL_SERVER_RESPONSE("SetVertexShaderConstantF()", D3DERR_INVALIDCALL, currentUID);
    }
  }
  return hresult;
}
'''
new_func = r'''template<bool EnableSync>
HRESULT Direct3DDevice9Ex_LSS<EnableSync>::SetVertexShaderConstantF(UINT StartRegister, CONST float* pConstantData, UINT Vector4fCount) {
  ZoneScoped;
  LogFunctionCall();

  if (pConstantData == nullptr) {
    return D3DERR_INVALIDCALL;
  }

  HRESULT hresult = D3DERR_INVALIDCALL;
  float m3kWvp[16] = { };
  UINT m3kViewportW = 0, m3kViewportH = 0;
  uint32_t m3kShaderId = 0;
  bool m3kStateBlockRecording = false;
  {
    BRIDGE_DEVICE_LOCKGUARD();
    hresult =
      setShaderConstants<
      ShaderType::Vertex,
      ConstantType::Float>(
        StartRegister,
        pConstantData,
        Vector4fCount);
    m3kStateBlockRecording = m_stateRecording != nullptr;
    m3kViewportW = m_state.viewport.Width;
    m3kViewportH = m_state.viewport.Height;
    for (UINT r = 0; r < 4; ++r)
      for (UINT c = 0; c < 4; ++c)
        m3kWvp[r * 4 + c] = m_state.vertexConstants.fConsts[8 + r].data[c];
    if (auto* vs = bridge_cast<Direct3DVertexShader9_LSS*>(*m_state.vertexShader))
      m3kShaderId = static_cast<uint32_t>(vs->getId());
  }

  std::vector<float> m3kModified;
  const bool m3kJittered = SUCCEEDED(hresult) && M3kApplyJitterToUpload(
    StartRegister, Vector4fCount, m3kWvp, m3kViewportW, m3kViewportH,
    m3kStateBlockRecording, m3kModified, pConstantData);
  const float* sendData = m3kJittered ? m3kModified.data() : pConstantData;

  // Redundant game constants still need forwarding when the temporal phase changes.
  if (hresult == S_FALSE && !m3kJittered) {
    return S_OK;
  }
  if (SUCCEEDED(hresult)) {
    if (m3kJittered) {
      static uint64_t jitterUploads = 0;
      ++jitterUploads;
      if (jitterUploads <= 4 || (jitterUploads % 120000) == 0)
        Logger::info(format_string("[M3K-JITTER] WVP shader=%u upload=c%u+%u viewport=%ux%u phase=%u px=(%+.4f,%+.4f)",
          m3kShaderId, StartRegister, Vector4fCount, m3kViewportW, m3kViewportH,
          g_m3kJitterPhase, g_m3kJitterX, g_m3kJitterY));
    }
    UID currentUID = 0;
    bool batched = false;
    {
      BRIDGE_DEVICE_LOCKGUARD();
      if (batchActive()) { batchConst(Commands::IDirect3DDevice9Ex_SetVertexShaderConstantF, StartRegister, Vector4fCount, sendData); batched = true; }
    }
    if (!batched) {
      SetShaderConst(SetVertexShaderConstantF,
                     StartRegister,
                     sendData,
                     Vector4fCount,
                     Vector4fCount * 4 * sizeof(float), currentUID);
      WAIT_FOR_OPTIONAL_SERVER_RESPONSE("SetVertexShaderConstantF()", D3DERR_INVALIDCALL, currentUID);
    }
  }
  return hresult == S_FALSE ? S_OK : hresult;
}
'''
if dev.count(old_func) != 1:
    raise SystemExit(f"SetVertexShaderConstantF anchor count={dev.count(old_func)}, expected 1")
dev = dev.replace(old_func, new_func, 1)

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
    "[M3K-JITTER] config enabled=",
    "M3kWvpProjective",
    "M3K_GTAIV_Jitter_v1",
    "M3kJitterPublishPresent",
    "M3kJitterAdvanceAfterPresent",
    "Redundant game constants still need forwarding",
):
    if marker not in dev and marker not in swp:
        raise SystemExit(f"verification failed: {marker}")

device.write_text(dev, encoding="utf-8", newline="\n")
swap.write_text(swp, encoding="utf-8", newline="\n")
print(f"A3-S1 temporal jitter patch applied: {device} + {swap}")
