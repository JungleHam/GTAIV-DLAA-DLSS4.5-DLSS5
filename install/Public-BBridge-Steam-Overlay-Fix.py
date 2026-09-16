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
if "[M3K-STEAM-V2]" in text:
    print("Public Steam overlay stack-aware client-rect exception already present")
    raise SystemExit(0)
if "[M3K-STEAM]" in text:
    raise SystemExit("old Steam overlay hotfix already present; apply v2 to a clean frozen UI-patched bridge source")

for required in ("[M3K-UI] config", "NewGetClientRect", "DETOURS_ATTACH(GetClientRect)", "forwarding WM_SIZE as logical"):
    if required not in text:
        raise SystemExit(f"expected frozen M3K UI virtualization marker missing: {required}")

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

new = r'''static bool M3kAddressBelongsToModule(const void* address, HMODULE wanted) {
  if (!address || !wanted)
    return false;

  HMODULE actual = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(address), &actual) ||
      !actual) {
    return false;
  }
  return actual == wanted;
}

static bool M3kStackContainsSteamOverlay() {
  // GTA IV is 32-bit, so Steam normally injects gameoverlayrenderer.dll.
  // Cache the handle once it appears; before Steam loads, there is nothing to match.
  static HMODULE steam32 = nullptr;
  static HMODULE steam64 = nullptr;
  if (!steam32)
    steam32 = GetModuleHandleW(L"gameoverlayrenderer.dll");
  if (!steam64)
    steam64 = GetModuleHandleW(L"gameoverlayrenderer64.dll");
  if (!steam32 && !steam64)
    return false;

  // Immediate-caller detection was insufficient on hardware because Steam can call
  // GetClientRect through another hook/wrapper. Inspect a short stack instead.
  void* frames[24] = { };
  const USHORT count = CaptureStackBackTrace(1, 24, frames, nullptr);
  for (USHORT i = 0; i < count; ++i) {
    if ((steam32 && M3kAddressBelongsToModule(frames[i], steam32)) ||
        (steam64 && M3kAddressBelongsToModule(frames[i], steam64))) {
      return true;
    }
  }
  return false;
}

DETOURS_DECL(GetClientRect);
static BOOL WINAPI NewGetClientRect(HWND hWnd, LPRECT lpRect) {
  const BOOL result = OrigGetClientRect(hWnd, lpRect);
  const bool steamOverlay = M3kStackContainsSteamOverlay();

  if (steamOverlay) {
    static bool logged = false;
    if (!logged) {
      Logger::info(format_string("[M3K-STEAM-V2] Steam overlay found in GetClientRect call stack; returning physical client extent"));
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
    "[M3K-STEAM-V2]",
    "gameoverlayrenderer.dll",
    "M3kStackContainsSteamOverlay",
    "CaptureStackBackTrace",
    "!steamOverlay && M3kUiVirtualActive",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"Public Steam overlay stack-aware client-rect exception applied: {source}")
