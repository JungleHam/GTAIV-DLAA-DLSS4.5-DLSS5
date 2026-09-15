#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: a3-s21-bbridge-native-jitter-gate.py <b-bridge-root>")

root = Path(sys.argv[1])
device = root / "src" / "client" / "d3d9_device.cpp"
if not device.is_file():
    raise SystemExit(f"missing b-bridge source: {device}")

text = device.read_text(encoding="utf-8")
if "M3K A3-S2: coherent draw-boundary" not in text:
    raise SystemExit("A3-S2 coherent draw jitter must be applied first")
if "A3-S2.1 Native/DLAA gate" in text:
    print("A3-S2.1 native jitter gate already present")
    raise SystemExit(0)

old_struct = '''struct M3kJitterConfig {
  bool enabled = false;
  uint32_t width = 0;
  uint32_t height = 0;
};'''
new_struct = '''struct M3kJitterConfig {
  // A3-S2.1 Native/DLAA gate: Native currently feeds NGX jitter=(0,0), so raster
  // jitter must be suppressed there. Preserve the user's request separately from
  // the effective bridge state so profile switches are explicit and reset history.
  bool requested = false;
  bool enabled = false;
  uint32_t profile = 0;
  uint32_t width = 0;
  uint32_t height = 0;
};'''
if old_struct not in text:
    raise SystemExit("could not find A3-S2 M3kJitterConfig struct")
text = text.replace(old_struct, new_struct, 1)

old_read = '''    next.enabled = GetPrivateProfileIntW(L"M3K", L"TemporalJitter", 0, path) != 0;
    next.width = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
    next.height = GetPrivateProfileIntW(L"M3K", L"RenderHeight", 0, path);'''
new_read = '''    next.requested = GetPrivateProfileIntW(L"M3K", L"TemporalJitter", 0, path) != 0;
    next.profile = static_cast<uint32_t>(GetPrivateProfileIntW(L"M3K", L"SRProfile", 0, path));
    next.enabled = next.requested && next.profile != 0u;
    next.width = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
    next.height = GetPrivateProfileIntW(L"M3K", L"RenderHeight", 0, path);'''
if old_read not in text:
    raise SystemExit("could not find A3-S2 INI read block")
text = text.replace(old_read, new_read, 1)

old_changed = '''  const bool changed = next.enabled != g_m3kJitterConfig.enabled ||
                       next.width != g_m3kJitterConfig.width ||
                       next.height != g_m3kJitterConfig.height;'''
new_changed = '''  const bool changed = next.requested != g_m3kJitterConfig.requested ||
                       next.enabled != g_m3kJitterConfig.enabled ||
                       next.profile != g_m3kJitterConfig.profile ||
                       next.width != g_m3kJitterConfig.width ||
                       next.height != g_m3kJitterConfig.height;'''
if old_changed not in text:
    raise SystemExit("could not find A3-S2 config-change block")
text = text.replace(old_changed, new_changed, 1)

old_log = '''    Logger::info(format_string("[M3K-JITTER] A3-S2 config enabled=%d render=%ux%u epoch=%ld",
      next.enabled ? 1 : 0, next.width, next.height, g_m3kJitterEpoch));'''
new_log = '''    Logger::info(format_string("[M3K-JITTER] A3-S2.1 config requested=%d effective=%d profile=%u render=%ux%u epoch=%ld",
      next.requested ? 1 : 0, next.enabled ? 1 : 0, next.profile, next.width, next.height, g_m3kJitterEpoch));
    if (next.requested && next.profile == 0u)
      Logger::info("[M3K-JITTER] A3-S2.1 Native/DLAA gate: raster jitter suppressed because Native NGX path reports jitter=(0,0)");'''
if old_log not in text:
    raise SystemExit("could not find A3-S2 config log")
text = text.replace(old_log, new_log, 1)

# Contract checks: only the effective `enabled` flag reaches draw/publish logic.
required = [
    "A3-S2.1 Native/DLAA gate",
    "next.enabled = next.requested && next.profile != 0u",
    "next.profile != g_m3kJitterConfig.profile",
    "Native NGX path reports jitter=(0,0)",
]
for marker in required:
    if marker not in text:
        raise SystemExit(f"missing generated A3-S2.1 marker: {marker}")

# Native profile must never turn effective bridge jitter on.
if "next.enabled = next.requested;" in text:
    raise SystemExit("unsafe unconditional jitter enable survived A3-S2.1")

device.write_text(text, encoding="utf-8")
print("Applied M3K A3-S2.1 Native/DLAA raster-jitter gate")
