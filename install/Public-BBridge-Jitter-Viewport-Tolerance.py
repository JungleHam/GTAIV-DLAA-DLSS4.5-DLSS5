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
text = text.replace(marker, marker + '\nstatic constexpr UINT kM3kViewportTolerancePx = 4u; // public regression fix', 1)
text = text.replace('dw > 4u || dh > 4u ||', 'dw > kM3kViewportTolerancePx || dh > kM3kViewportTolerancePx ||', 1)

device.write_text(text, encoding="utf-8", newline="\n")
print("Applied GTA IV temporal-jitter viewport tolerance: +/-4 px")
