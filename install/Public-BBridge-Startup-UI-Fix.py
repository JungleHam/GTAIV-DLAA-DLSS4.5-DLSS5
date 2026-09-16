#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-Startup-UI-Fix.py <b-bridge-root>")

root = Path(sys.argv[1])
source = root / "src" / "client" / "window.cpp"
if not source.is_file():
    raise SystemExit(f"missing b-bridge source: {source}")

text = source.read_text(encoding="utf-8")
if "[M3K-UI-STARTUP]" in text:
    print("Public startup UI resync patch already present")
    raise SystemExit(0)

for required in ("[M3K-UI] config", "NewGetClientRect", "config-change resync WM_SIZE logical"):
    if required not in text:
        raise SystemExit(f"expected frozen A2-S2.1 UI virtualization marker missing: {required}")

anchor = "  DInputSetDefaultWindow(hwnd);\n\n  Logger::debug(format_string(kStr_set_settingWndProc, RemixWndProc, g_gameWndProc));\n"
replacement = r'''  DInputSetDefaultWindow(hwnd);

  // Public startup fix: the first INI poll can happen before the bridge owns the
  // game's WndProc, so the A2-S2.1 config-change resync deliberately has no window
  // to notify. Once attachment succeeds, send one logical WM_SIZE immediately.
  // This initializes GTA's HUD/map/weapon-wheel coordinate state without changing
  // the real presenter-sized HWND or forcing a user-visible 1080p display mode.
  {
    const auto config = M3kGetUiConfig();
    if (config.enabled && config.width && config.height && g_gameWndProc) {
      const BOOL posted = PostMessageW(hwnd, WM_SIZE, SIZE_RESTORED,
        MAKELPARAM(config.width, config.height));
      Logger::info(format_string("[M3K-UI-STARTUP] initial logical WM_SIZE %ux%u posted=%d",
        config.width, config.height, posted ? 1 : 0));
    }
  }

  Logger::debug(format_string(kStr_set_settingWndProc, RemixWndProc, g_gameWndProc));
'''

if text.count(anchor) != 1:
    raise SystemExit(f"startup UI set() anchor count={text.count(anchor)}, expected 1")
text = text.replace(anchor, replacement, 1)

for marker in ("[M3K-UI-STARTUP]", "initial logical WM_SIZE", "M3kGetUiConfig()"):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"Public b-bridge startup UI resync patch applied: {source}")
