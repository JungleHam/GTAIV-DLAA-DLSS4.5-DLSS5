#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-Steam-WMSize-Fix.py <b-bridge-root>")

root = Path(sys.argv[1])
source = root / "src" / "client" / "window.cpp"
if not source.is_file():
    raise SystemExit(f"missing b-bridge source: {source}")

text = source.read_text(encoding="utf-8")
if "[M3K-STEAM-WMSIZE]" in text:
    print("Public Steam WM_SIZE split patch already present")
    raise SystemExit(0)

for required in ("[M3K-UI] config", "NewGetClientRect", "DETOURS_ATTACH(GetClientRect)", "forwarding WM_SIZE as logical"):
    if required not in text:
        raise SystemExit(f"expected frozen M3K UI virtualization marker missing: {required}")

include_anchor = "#include <d3d9.h>\n"
include_new = "#include <d3d9.h>\n#include <intrin.h>\n"
if text.count(include_anchor) != 1:
    raise SystemExit(f"intrin include anchor count={text.count(include_anchor)}, expected 1")
text = text.replace(include_anchor, include_new, 1)

# Add Steam module helpers immediately after M3kUiVirtualActive.
helper_anchor = r'''static bool M3kUiVirtualActive(HWND hWnd, M3kUiConfig* out = nullptr) {
  const auto config = M3kGetUiConfig();
  if (out)
    *out = config;
  return config.enabled && hWnd && hWnd == g_hwnd && config.width && config.height;
}
'''
helper_new = helper_anchor + r'''
static bool M3kModuleIsSteamOverlay(HMODULE module) {
  if (!module)
    return false;
  const HMODULE steam32 = GetModuleHandleW(L"gameoverlayrenderer.dll");
  const HMODULE steam64 = GetModuleHandleW(L"gameoverlayrenderer64.dll");
  return (steam32 && module == steam32) || (steam64 && module == steam64);
}

static bool M3kAddressIsSteamOverlay(const void* address) {
  if (!address)
    return false;
  HMODULE module = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(address), &module))
    return false;
  return M3kModuleIsSteamOverlay(module);
}

static bool M3kWndProcIsSteamOverlay(WNDPROC proc) {
  return proc && M3kAddressIsSteamOverlay(reinterpret_cast<const void*>(proc));
}
'''
if text.count(helper_anchor) != 1:
    raise SystemExit(f"UI helper anchor count={text.count(helper_anchor)}, expected 1")
text = text.replace(helper_anchor, helper_new, 1)

# Insert CallWindowProc detours after the existing GetClientRect hook.
getrect_anchor = r'''DETOURS_ASSIGN_NEW_FUNC(GetClientRect, NewGetClientRect);
DETOURS_DECL_ASSERT(GetClientRect);
'''
callproc_block = getrect_anchor + r'''

template<bool bUnicode>
static LRESULT WINAPI NewCallWindowProc(WNDPROC lpPrevWndFunc, HWND hWnd, UINT Msg,
                                        WPARAM wParam, LPARAM lParam) {
  LPARAM forwardedLParam = lParam;
  M3kUiConfig config;

  // When Steam subclasses GTA's HWND underneath b-bridge, b-bridge first gives
  // Steam a physical WM_SIZE. Steam then forwards that message to GTA through
  // CallWindowProc. Rewrite only Steam's downstream copy back to the logical
  // DLSS render extent so GTA's HUD/menu coordinates remain correct.
  if (Msg == WM_SIZE && wParam != SIZE_MINIMIZED && hWnd == g_hwnd &&
      M3kAddressIsSteamOverlay(_ReturnAddress()) &&
      M3kUiVirtualActive(hWnd, &config)) {
    forwardedLParam = MAKELPARAM(config.width, config.height);
    static uint32_t lastW = 0, lastH = 0;
    if (lastW != config.width || lastH != config.height) {
      Logger::info(format_string("[M3K-STEAM-WMSIZE] Steam CallWindowProc -> GTA logical %ux%u",
        config.width, config.height));
      lastW = config.width;
      lastH = config.height;
    }
  }

  if constexpr (bUnicode)
    return OrigCallWindowProcW(lpPrevWndFunc, hWnd, Msg, wParam, forwardedLParam);
  else
    return OrigCallWindowProcA(lpPrevWndFunc, hWnd, Msg, wParam, forwardedLParam);
}
DETOURS_FUNC__UNICODE(CallWindowProc, NewCallWindowProc<true>, NewCallWindowProc<false>);
'''
if text.count(getrect_anchor) != 1:
    raise SystemExit(f"GetClientRect detour anchor count={text.count(getrect_anchor)}, expected 1")
text = text.replace(getrect_anchor, callproc_block, 1)

attach_old = "  bSuccess &= DETOURS_ATTACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_ATTACH(GetClientRect);\n  DetourTransactionCommit();\n"
attach_new = "  bSuccess &= DETOURS_ATTACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_ATTACH(GetClientRect);\n  bSuccess &= DETOURS_ATTACH__UNICODE(CallWindowProc);\n  DetourTransactionCommit();\n"
if text.count(attach_old) != 1:
    raise SystemExit(f"attach anchor count={text.count(attach_old)}, expected 1")
text = text.replace(attach_old, attach_new, 1)

detach_old = "  bSuccess &= DETOURS_DETACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_DETACH(GetClientRect);\n  DetourTransactionCommit();\n"
detach_new = "  bSuccess &= DETOURS_DETACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_DETACH(GetClientRect);\n  bSuccess &= DETOURS_DETACH__UNICODE(CallWindowProc);\n  DetourTransactionCommit();\n"
if text.count(detach_old) != 1:
    raise SystemExit(f"detach anchor count={text.count(detach_old)}, expected 1")
text = text.replace(detach_old, detach_new, 1)

# Replace the existing logical WM_SIZE forwarding block. If Steam owns the
# WndProc below us, it gets the real physical presenter extent. Its subsequent
# CallWindowProc into GTA is detoured above and converted back to logical.
wnd_old = r'''    LPARAM gameLParam = lParam;
    M3kUiConfig config;
    if (msg == WM_SIZE && wParam != SIZE_MINIMIZED && M3kUiVirtualActive(hWnd, &config)) {
      gameLParam = MAKELPARAM(config.width, config.height);
      static uint32_t lastW = 0, lastH = 0;
      if (lastW != config.width || lastH != config.height) {
        Logger::info(format_string("[M3K-UI] forwarding WM_SIZE as logical %ux%u while physical HWND remains presenter-sized",
          config.width, config.height));
        lastW = config.width;
        lastH = config.height;
      }
    }
'''
wnd_new = r'''    LPARAM gameLParam = lParam;
    M3kUiConfig config;
    if (msg == WM_SIZE && wParam != SIZE_MINIMIZED && M3kUiVirtualActive(hWnd, &config)) {
      if (M3kWndProcIsSteamOverlay(g_gameWndProc)) {
        RECT physical = { };
        if (OrigGetClientRect && OrigGetClientRect(hWnd, &physical)) {
          const uint32_t physicalW = uint32_t((std::max)(LONG(0), physical.right - physical.left));
          const uint32_t physicalH = uint32_t((std::max)(LONG(0), physical.bottom - physical.top));
          if (physicalW && physicalH)
            gameLParam = MAKELPARAM(physicalW, physicalH);

          static uint32_t lastPhysicalW = 0, lastPhysicalH = 0;
          static uint32_t lastLogicalW = 0, lastLogicalH = 0;
          if (lastPhysicalW != physicalW || lastPhysicalH != physicalH ||
              lastLogicalW != config.width || lastLogicalH != config.height) {
            Logger::info(format_string("[M3K-STEAM-WMSIZE] Steam WndProc receives physical %ux%u; GTA target logical %ux%u",
              physicalW, physicalH, config.width, config.height));
            lastPhysicalW = physicalW;
            lastPhysicalH = physicalH;
            lastLogicalW = config.width;
            lastLogicalH = config.height;
          }
        }
      } else {
        gameLParam = MAKELPARAM(config.width, config.height);
        static uint32_t lastW = 0, lastH = 0;
        if (lastW != config.width || lastH != config.height) {
          Logger::info(format_string("[M3K-UI] forwarding WM_SIZE as logical %ux%u while physical HWND remains presenter-sized",
            config.width, config.height));
          lastW = config.width;
          lastH = config.height;
        }
      }
    }
'''
if text.count(wnd_old) != 1:
    raise SystemExit(f"WndProc logical forwarding anchor count={text.count(wnd_old)}, expected 1")
text = text.replace(wnd_old, wnd_new, 1)

for marker in (
    "[M3K-STEAM-WMSIZE]",
    "Steam WndProc receives physical",
    "Steam CallWindowProc -> GTA logical",
    "M3kWndProcIsSteamOverlay",
    "DETOURS_ATTACH__UNICODE(CallWindowProc)",
    "M3kAddressIsSteamOverlay(_ReturnAddress())",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

if "[M3K-UI-STARTUP]" in text:
    raise SystemExit("rejected startup-resync patch present")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"Public Steam WM_SIZE split patch applied: {source}")
