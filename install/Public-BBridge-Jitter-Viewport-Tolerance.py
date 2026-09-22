#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-Jitter-Viewport-Tolerance.py <b-bridge-root>")

root = Path(sys.argv[1])
device = root / "src" / "client" / "d3d9_device.cpp"
if not device.is_file():
    raise SystemExit(f"missing b-bridge source: {device}")

text = device.read_text(encoding="utf-8")
old = """  if (!config.enabled || !config.width || !config.height ||
      viewportWidth != config.width || viewportHeight != config.height ||
      !M3kWvpProjective(originalWvp))
    return false;
"""
new = """  // GTA IV can expose the main scene viewport a few pixels smaller than the
  // logical render size after a live D3D9/DXVK resize. Current hardware logs show
  // 2560x1440 -> 2558/2559x1440 and 1971x1109 -> 1968..1970x1109.
  // Exact equality silently disables temporal jitter, so accept only a tiny
  // +/-4 px neighbourhood. UI/offscreen viewports remain far outside this gate.
  const UINT dw = viewportWidth > config.width ? viewportWidth - config.width : config.width - viewportWidth;
  const UINT dh = viewportHeight > config.height ? viewportHeight - config.height : config.height - viewportHeight;
  if (!config.enabled || !config.width || !config.height ||
      dw > 4u || dh > 4u ||
      !M3kWvpProjective(originalWvp))
    return false;
"""

count = text.count(old)
if count != 1:
    raise SystemExit(f"viewport exact-match block count={count}, expected 1")
text = text.replace(old, new, 1)

marker = 'static constexpr uint32_t kM3kJitterPhases = 16u;'
if marker not in text:
    raise SystemExit("A3-S2 jitter marker missing after patch")
text = text.replace(
    marker,
    'static constexpr uint32_t kM3kJitterDefaultPhases = 16u;\n'
    'static constexpr uint32_t kM3kJitterMaxPhases = 1024u;\n'
    'static constexpr UINT kM3kViewportTolerancePx = 4u; // public regression fix',
    1)
text = text.replace('dw > 4u || dh > 4u ||', 'dw > kM3kViewportTolerancePx || dh > kM3kViewportTolerancePx ||', 1)

# Add a live phase count to the bridge-side jitter config.
old_struct = """struct M3kJitterConfig {
  bool enabled = false;
  uint32_t width = 0;
  uint32_t height = 0;
};
"""
new_struct = """struct M3kJitterConfig {
  bool enabled = false;
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t phases = 16u;
};
"""
if text.count(old_struct) != 1:
    raise SystemExit(f"jitter config struct count={text.count(old_struct)}, expected 1")
text = text.replace(old_struct, new_struct, 1)

old_phase = '  g_m3kJitterPhase = phase % kM3kJitterPhases;'
new_phase = """  const uint32_t phases = g_m3kJitterConfig.phases >= 2u
    ? g_m3kJitterConfig.phases : kM3kJitterDefaultPhases;
  g_m3kJitterPhase = phase % phases;"""
if text.count(old_phase) != 1:
    raise SystemExit(f"phase modulo count={text.count(old_phase)}, expected 1")
text = text.replace(old_phase, new_phase, 1)

old_read = """    next.enabled = GetPrivateProfileIntW(L"M3K", L"TemporalJitter", 0, path) != 0;
    next.width = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
    next.height = GetPrivateProfileIntW(L"M3K", L"RenderHeight", 0, path);
"""
new_read = """    next.enabled = GetPrivateProfileIntW(L"M3K", L"TemporalJitter", 0, path) != 0;
    next.width = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
    next.height = GetPrivateProfileIntW(L"M3K", L"RenderHeight", 0, path);
    UINT rawPhases = GetPrivateProfileIntW(L"M3K", L"JitterPhases", kM3kJitterDefaultPhases, path);
    if (rawPhases < 2u) rawPhases = kM3kJitterDefaultPhases;
    if (rawPhases > kM3kJitterMaxPhases) rawPhases = kM3kJitterMaxPhases;
    next.phases = rawPhases;
"""
if text.count(old_read) != 1:
    raise SystemExit(f"jitter config read count={text.count(old_read)}, expected 1")
text = text.replace(old_read, new_read, 1)

old_changed = """  const bool changed = next.enabled != g_m3kJitterConfig.enabled ||
                       next.width != g_m3kJitterConfig.width ||
                       next.height != g_m3kJitterConfig.height;
"""
new_changed = """  const bool changed = next.enabled != g_m3kJitterConfig.enabled ||
                       next.width != g_m3kJitterConfig.width ||
                       next.height != g_m3kJitterConfig.height ||
                       next.phases != g_m3kJitterConfig.phases;
"""
if text.count(old_changed) != 1:
    raise SystemExit(f"jitter config changed block count={text.count(old_changed)}, expected 1")
text = text.replace(old_changed, new_changed, 1)

old_log = """    Logger::info(format_string("[M3K-JITTER] A3-S2 config enabled=%d render=%ux%u epoch=%ld",
      next.enabled ? 1 : 0, next.width, next.height, g_m3kJitterEpoch));
"""
new_log = """    Logger::info(format_string("[M3K-JITTER] A3-S2 config enabled=%d render=%ux%u phases=%u epoch=%ld",
      next.enabled ? 1 : 0, next.width, next.height, next.phases, g_m3kJitterEpoch));
"""
if text.count(old_log) != 1:
    raise SystemExit(f"jitter config log count={text.count(old_log)}, expected 1")
text = text.replace(old_log, new_log, 1)

device.write_text(text, encoding="utf-8", newline="\n")
print("Applied GTA IV temporal-jitter viewport tolerance +/-4 px + live phase count")
