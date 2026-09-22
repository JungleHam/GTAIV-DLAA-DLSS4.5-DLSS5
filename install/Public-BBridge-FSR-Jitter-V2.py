#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-FSR-Jitter-V2.py <b-bridge-root>")

root = Path(sys.argv[1])
device = root / "src" / "client" / "d3d9_device.cpp"
if not device.is_file():
    raise SystemExit(f"missing b-bridge source: {device}")

text = device.read_text(encoding="utf-8")

def once(old: str, new: str, label: str):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)

# P4 is deliberately backend-specific. The existing NVIDIA/DLSS raster sequence is
# hardware-proven and remains unchanged when FSRProof=0. FSR gets AMD's exact helper
# convention: Halton((index % phaseCount)+1) - 0.5, which never emits a null (0,0) vector.
once(
"""struct M3kJitterConfig {
  bool enabled = false;
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t phases = 16u;
};
""",
"""struct M3kJitterConfig {
  bool enabled = false;
  bool fsr = false;
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t phases = 16u;
};
""",
"jitter config backend flag")

once(
"""struct M3kJitterSharedV1 {
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
""",
"""struct M3kJitterSharedV1 {
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
  LONG phase;
  LONG phaseCount;
  LONG sequenceKind; // 0 = protected DLSS legacy sequence, 1 = AMD FSR helper-compatible sequence
};
""",
"shared jitter v2 fields")

once(
"static constexpr uint32_t kM3kJitterVersion = 1u;",
"static constexpr uint32_t kM3kJitterVersion = 2u;",
"shared jitter version")

text = text.replace('Local\\\\M3K_GTAIV_Jitter_v1', 'Local\\\\M3K_GTAIV_Jitter_v2')
if 'Local\\\\M3K_GTAIV_Jitter_v1' in text:
    raise SystemExit("old jitter mapping name remains")

start = text.find("static void M3kJitterSetPhase(uint32_t phase) {")
end = text.find("\n}\n\nstatic M3kJitterConfig M3kGetJitterConfig()", start)
if start < 0 or end < 0:
    raise SystemExit("jitter phase function markers missing")
old = text[start:end+3]
new = r'''static void M3kJitterSetPhase(uint32_t phase) {
  const uint32_t phases = g_m3kJitterConfig.phases >= 2u
    ? g_m3kJitterConfig.phases : kM3kJitterDefaultPhases;
  g_m3kJitterPhase = phase % phases;

  if (g_m3kJitterConfig.fsr) {
    // Match ffxFsr3UpscalerGetJitterOffset exactly:
    // halton((index % phaseCount) + 1, base) - 0.5.
    // In particular phase 0 becomes (0, -1/6), NOT the DLSS-era null vector.
    const uint32_t amdIndex = g_m3kJitterPhase + 1u;
    g_m3kJitterX = M3kHalton(amdIndex, 2u) - 0.5f;
    g_m3kJitterY = M3kHalton(amdIndex, 3u) - 0.5f;
  } else if (g_m3kJitterPhase == 0) {
    // Preserve the hardware-proven NVIDIA/DLSS sequence byte-for-behaviour.
    g_m3kJitterX = 0.0f;
    g_m3kJitterY = 0.0f;
  } else {
    g_m3kJitterX = M3kHalton(g_m3kJitterPhase, 2u) - 0.5f;
    g_m3kJitterY = M3kHalton(g_m3kJitterPhase, 3u) - 0.5f;
  }
}
'''
text = text[:start] + new + text[end+3:]

once(
"""    next.enabled = GetPrivateProfileIntW(L"M3K", L"TemporalJitter", 0, path) != 0;
    next.width = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
""",
"""    next.enabled = GetPrivateProfileIntW(L"M3K", L"TemporalJitter", 0, path) != 0;
    next.fsr = GetPrivateProfileIntW(L"M3K", L"FSRProof", 0, path) != 0;
    next.width = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
""",
"FSR selection read")

once(
"""  const bool changed = next.enabled != g_m3kJitterConfig.enabled ||
                       next.width != g_m3kJitterConfig.width ||
                       next.height != g_m3kJitterConfig.height ||
                       next.phases != g_m3kJitterConfig.phases;
""",
"""  const bool changed = next.enabled != g_m3kJitterConfig.enabled ||
                       next.fsr != g_m3kJitterConfig.fsr ||
                       next.width != g_m3kJitterConfig.width ||
                       next.height != g_m3kJitterConfig.height ||
                       next.phases != g_m3kJitterConfig.phases;
""",
"backend change detection")

once(
"""    Logger::info(format_string("[M3K-JITTER] A3-S2 config enabled=%d render=%ux%u phases=%u epoch=%ld",
      next.enabled ? 1 : 0, next.width, next.height, next.phases, g_m3kJitterEpoch));
""",
"""    Logger::info(format_string("[M3K-JITTER] P4 config enabled=%d backend=%s render=%ux%u phases=%u epoch=%ld",
      next.enabled ? 1 : 0, next.fsr ? "FSR-AMD" : "DLSS-LEGACY",
      next.width, next.height, next.phases, g_m3kJitterEpoch));
""",
"backend config log")

once(
"""  s->jitterX = active ? g_m3kJitterX : 0.0f;
  s->jitterY = active ? g_m3kJitterY : 0.0f;
  MemoryBarrier();
""",
"""  s->jitterX = active ? g_m3kJitterX : 0.0f;
  s->jitterY = active ? g_m3kJitterY : 0.0f;
  s->phase = active ? static_cast<LONG>(g_m3kJitterPhase) : -1;
  s->phaseCount = static_cast<LONG>(config.phases);
  s->sequenceKind = config.fsr ? 1 : 0;
  MemoryBarrier();
""",
"published temporal metadata")

once(
"""    Logger::info(format_string("[M3K-JITTER] A3-S2 publish frame=%ld epoch=%ld phase=%u px=(%+.4f,%+.4f) render=%ux%u",
      frame, g_m3kJitterEpoch, g_m3kJitterPhase, g_m3kJitterX, g_m3kJitterY,
      config.width, config.height));
""",
"""    Logger::info(format_string("[M3K-JITTER] P4 publish frame=%ld epoch=%ld seq=%s phase=%u/%u px=(%+.4f,%+.4f) render=%ux%u",
      frame, g_m3kJitterEpoch, config.fsr ? "FSR-AMD" : "DLSS-LEGACY",
      g_m3kJitterPhase, config.phases, g_m3kJitterX, g_m3kJitterY,
      config.width, config.height));
""",
"published temporal log")

for marker in (
    'backend=%s',
    'FSR-AMD',
    'DLSS-LEGACY',
    'amdIndex = g_m3kJitterPhase + 1u',
    's->phaseCount',
    's->sequenceKind',
    'Local\\\\M3K_GTAIV_Jitter_v2',
    'kM3kJitterVersion = 2u',
):
    if marker not in text:
        raise SystemExit(f"P4 bridge verification marker missing: {marker}")

device.write_text(text, encoding="utf-8", newline="\n")
print("Applied P4 backend-specific jitter: DLSS preserved; FSR matches AMD helper + V2 handoff")
