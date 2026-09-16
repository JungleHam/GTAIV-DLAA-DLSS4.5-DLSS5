#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-Steam-Overlay-Fix.py <b-bridge-root>")

root = Path(sys.argv[1])
source = root / "src" / "client" / "window.cpp"
if not source.is_file():
    raise SystemExit(f"missing b-bridge source: {source}")

text = source.read_text(encoding="utf-8")
if "[M3K-STEAM]" in text:
    print("Public Steam overlay client-rect exception already present")
    raise SystemExit(0)

for required in ("[M3K-UI] config", "NewGetClientRect", "DETOURS_ATTACH(GetClientRect)", "forwarding WM_SIZE as logical"):
    if required not in text:
        raise SystemExit(f"expected frozen M3K UI virtualization marker missing: {required}")

include_anchor = "#include <d3d9.h>\n"
include_new = "#include <d3d9.h>\n#include <intrin.h>\n"
if text.count(include_anchor) != 1:
    raise SystemExit(f"intrin include anchor count={text.count(include_anchor)}, expected 1")
text = text.replace(include_anchor, include_new, 1)

old = r'''DETOURS_DECL(GetClientRect);
static BOOL WINAPI NewGetClientRect(HWND hWnd, LPRECT lpRect) {
  const BOOL result = OrigGetClientRect(hWnd, lpRect);
  M3kUiConfig config;
  if (result && lpRect && M3kUiVirtualActive(hWnd, &config)) {
    lpRect->right = lpRect->left + LONG(config.width);
    lpRect->bottom = lpRect->top + LONG(config.height);
  }
  return result;
}
DETOURS_ASSIGN_NEW_FUNC(GetClientRect, NewGetClientRect);
DETOURS_DECL_ASSERT(GetClientRect);
'''

new = r'''static bool M3kCallerIsSteamOverlay(const void* callerAddress) {
  if (!callerAddress)
    return false;

  HMODULE callerModule = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(callerAddress), &callerModule) ||
      !callerModule) {
    return false;
  }

  // GTA IV is 32-bit, so Steam normally injects gameoverlayrenderer.dll.
  // Keep the 64-bit name too so this helper remains harmless if reused elsewhere.
  static HMODULE steam32 = nullptr;
  static HMODULE steam64 = nullptr;
  if (!steam32)
    steam32 = GetModuleHandleW(L"gameoverlayrenderer.dll");
  if (!steam64)
    steam64 = GetModuleHandleW(L"gameoverlayrenderer64.dll");

  return (steam32 && callerModule == steam32) ||
         (steam64 && callerModule == steam64);
}

DETOURS_DECL(GetClientRect);
static BOOL WINAPI NewGetClientRect(HWND hWnd, LPRECT lpRect) {
  // _ReturnAddress here is the module that called the detoured Win32 API.
  // GTA itself should continue seeing the logical DLSS render extent, while
  // Steam's overlay needs the real presenter-sized client extent for anchoring.
  const void* callerAddress = _ReturnAddress();
  const BOOL result = OrigGetClientRect(hWnd, lpRect);
  const bool steamOverlay = M3kCallerIsSteamOverlay(callerAddress);

  if (steamOverlay) {
    static bool logged = false;
    if (!logged) {
      Logger::info(format_string("[M3K-STEAM] Steam overlay GetClientRect bypass active; returning physical client extent"));
      logged = true;
    }
  }

  M3kUiConfig config;
  if (result && lpRect && !steamOverlay && M3kUiVirtualActive(hWnd, &config)) {
    lpRect->right = lpRect->left + LONG(config.width);
    lpRect->bottom = lpRect->top + LONG(config.height);
  }
  return result;
}
DETOURS_ASSIGN_NEW_FUNC(GetClientRect, NewGetClientRect);
DETOURS_DECL_ASSERT(GetClientRect);
'''

if text.count(old) != 1:
    raise SystemExit(f"GetClientRect wrapper anchor count={text.count(old)}, expected 1")
text = text.replace(old, new, 1)

for marker in (
    "[M3K-STEAM]",
    "gameoverlayrenderer.dll",
    "M3kCallerIsSteamOverlay",
    "_ReturnAddress()",
    "!steamOverlay && M3kUiVirtualActive",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"Public Steam overlay client-rect exception applied: {source}")
