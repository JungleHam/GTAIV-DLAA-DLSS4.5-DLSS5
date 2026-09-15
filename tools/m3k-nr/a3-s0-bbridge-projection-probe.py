#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: a3-s0-bbridge-projection-probe.py <b-bridge-root>")

root = Path(sys.argv[1])
source = root / "src" / "client" / "d3d9_device.cpp"
if not source.is_file():
    raise SystemExit(f"missing b-bridge source: {source}")

text = source.read_text(encoding="utf-8")
if "[M3K-JITTER-PROBE]" in text:
    print("A3-S0 projection probe already present")
    raise SystemExit(0)

# Diagnostic only: do not modify any shader constants.  We sample 4x4-aligned
# windows from GTA IV vertex-float uploads and tag them by vertex-shader object and
# absolute register.  The runtime test will tell us which block behaves like the
# camera projection/view-projection matrix before A3-S1 attempts real raster jitter.
helper_anchor = "extern SwapChainMap gSwapChainMap;\n"
helper_new = r'''extern SwapChainMap gSwapChainMap;

// M3K A3-S0: projection discovery.  This is intentionally read-only: no constant
// data is changed.  ProjectionProbe=1 in .trex\\m3k-nr.ini enables rate-limited
// samples of 4x4 vertex-constant windows so GTA IV's camera matrix can be found
// empirically before real temporal jitter is introduced.
static bool M3kProjectionProbeConfigPath(wchar_t* path, size_t pathCount) {
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

static bool M3kProjectionProbeEnabled() {
  static bool enabled = false;
  static bool first = true;
  static ULONGLONG nextPoll = 0;
  const ULONGLONG now = GetTickCount64();
  if (now < nextPoll)
    return enabled;
  nextPoll = now + 1000;

  wchar_t path[MAX_PATH] = { };
  bool next = false;
  if (M3kProjectionProbeConfigPath(path, MAX_PATH))
    next = GetPrivateProfileIntW(L"M3K", L"ProjectionProbe", 0, path) != 0;
  if (first || next != enabled) {
    Logger::info(format_string("[M3K-JITTER-PROBE] enabled=%d (read-only vertex constant discovery)", next ? 1 : 0));
    first = false;
  }
  enabled = next;
  return enabled;
}

struct M3kProjectionProbeEntry {
  uint32_t shaderId = 0;
  uint32_t reg = 0;
  uint64_t samples = 0;
  uint64_t lastHash = 0;
  bool used = false;
};

static uint64_t M3kProjectionProbeHash(const float* v) {
  uint64_t hash = 1469598103934665603ull;
  for (uint32_t i = 0; i < 16; ++i) {
    uint32_t bits = 0;
    memcpy(&bits, v + i, sizeof(bits));
    hash ^= bits;
    hash *= 1099511628211ull;
  }
  return hash;
}

static bool M3kProjectionProbePerspectiveLike(const float* m) {
  // Raw perspective matrices usually have a strong diagonal, m33 ~= 0 and a
  // +/-1 perspective term.  Combined view-projection matrices need not match,
  // so non-matching windows are still sampled at a lower rate.
  const float a0 = fabsf(m[0]);
  const float a5 = fabsf(m[5]);
  const float a15 = fabsf(m[15]);
  const float a11 = fabsf(m[11]);
  const float a14 = fabsf(m[14]);
  return a0 > 0.02f && a5 > 0.02f && a15 < 0.15f &&
         (fabsf(a11 - 1.0f) < 0.30f || fabsf(a14 - 1.0f) < 0.30f);
}

static void M3kProjectionProbeConstants(uint32_t shaderId, UINT startRegister,
                                        const float* data, UINT vectorCount) {
  if (!M3kProjectionProbeEnabled() || data == nullptr || vectorCount < 4)
    return;

  static M3kProjectionProbeEntry entries[256] = { };
  uint32_t windows = 0;
  for (UINT offset = 0; offset + 4 <= vectorCount && windows < 8; offset += 4, ++windows) {
    const uint32_t reg = startRegister + offset;
    M3kProjectionProbeEntry* entry = nullptr;
    for (auto& candidate : entries) {
      if (candidate.used && candidate.shaderId == shaderId && candidate.reg == reg) {
        entry = &candidate;
        break;
      }
      if (!candidate.used && entry == nullptr)
        entry = &candidate;
    }
    if (entry == nullptr)
      continue;
    if (!entry->used) {
      entry->used = true;
      entry->shaderId = shaderId;
      entry->reg = reg;
    }

    const float* m = data + offset * 4;
    const uint64_t hash = M3kProjectionProbeHash(m);
    const bool changed = entry->samples == 0 || hash != entry->lastHash;
    const bool perspective = M3kProjectionProbePerspectiveLike(m);
    ++entry->samples;
    entry->lastHash = hash;

    // First two samples establish the block.  Perspective-looking blocks get a
    // short burst plus one sample every 120 writes; everything else is only
    // repeated every 600 writes.  This keeps bridge32.log useful instead of huge.
    const bool emit = entry->samples <= 2 ||
                      (perspective && changed && (entry->samples <= 16 || (entry->samples % 120) == 0)) ||
                      (changed && (entry->samples % 600) == 0);
    if (!emit)
      continue;

    Logger::info(format_string(
      "[M3K-JITTER-PROBE] shader=%u reg=c%u uploadStart=c%u uploadCount=%u sample=%llu changed=%d perspective=%d "
      "m=[%.7g %.7g %.7g %.7g | %.7g %.7g %.7g %.7g | %.7g %.7g %.7g %.7g | %.7g %.7g %.7g %.7g]",
      shaderId, reg, startRegister, vectorCount,
      static_cast<unsigned long long>(entry->samples), changed ? 1 : 0, perspective ? 1 : 0,
      m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7],
      m[8], m[9], m[10], m[11], m[12], m[13], m[14], m[15]));
  }
}
'''
if text.count(helper_anchor) != 1:
    raise SystemExit(f"helper anchor count={text.count(helper_anchor)}, expected 1")
text = text.replace(helper_anchor, helper_new, 1)

func_old = r'''  HRESULT hresult = D3DERR_INVALIDCALL;
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
'''
func_new = r'''  HRESULT hresult = D3DERR_INVALIDCALL;
  uint32_t m3kShaderId = 0;
  {
    BRIDGE_DEVICE_LOCKGUARD();
    hresult =
      setShaderConstants<
      ShaderType::Vertex,
      ConstantType::Float>(
        StartRegister,
        pConstantData,
        Vector4fCount);
    if (auto* vs = bridge_cast<Direct3DVertexShader9_LSS*>(*m_state.vertexShader))
      m3kShaderId = static_cast<uint32_t>(vs->getId());
  }
  if (SUCCEEDED(hresult))
    M3kProjectionProbeConstants(m3kShaderId, StartRegister, pConstantData, Vector4fCount);
  if (hresult == S_FALSE) {
'''
if text.count(func_old) != 1:
    raise SystemExit(f"SetVertexShaderConstantF anchor count={text.count(func_old)}, expected 1")
text = text.replace(func_old, func_new, 1)

for marker in (
    "[M3K-JITTER-PROBE] enabled=",
    "M3kProjectionProbeConstants",
    "ProjectionProbe",
    "read-only vertex constant discovery",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"A3-S0 b-bridge projection probe applied: {source}")
