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
for old_marker in ("[M3K-STEAM]", "[M3K-STEAM-V2]", "[M3K-STEAM-V3]"):
    if old_marker in text:
        raise SystemExit(f"Steam overlay hotfix already present ({old_marker}); apply v3 to clean frozen UI-patched bridge source")

for required in (
    "[M3K-UI] config",
    "NewGetClientRect",
    "DETOURS_ATTACH(GetClientRect)",
    "forwarding WM_SIZE as logical",
):
    if required not in text:
        raise SystemExit(f"expected frozen M3K UI virtualization marker missing: {required}")

# Add Steam module / stack helpers immediately before the existing GetClientRect detour.
hook_anchor = "DETOURS_DECL(GetClientRect);\n"
helper = r'''static bool M3kAddressBelongsToSteamOverlay(const void* address) {
  if (!address)
    return false;

  static HMODULE steam32 = nullptr;
  static HMODULE steam64 = nullptr;
  if (!steam32)
    steam32 = GetModuleHandleW(L"gameoverlayrenderer.dll");
  if (!steam64)
    steam64 = GetModuleHandleW(L"gameoverlayrenderer64.dll");
  if (!steam32 && !steam64)
    return false;

  HMODULE actual = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(address), &actual) ||
      !actual) {
    return false;
  }

  return (steam32 && actual == steam32) || (steam64 && actual == steam64);
}

static bool M3kStackContainsSteamOverlay() {
  void* frames[24] = { };
  const USHORT count = CaptureStackBackTrace(1, 24, frames, nullptr);
  for (USHORT i = 0; i < count; ++i) {
    if (M3kAddressBelongsToSteamOverlay(frames[i]))
      return true;
  }
  return false;
}

DETOURS_DECL(GetClientRect);
'''
if text.count(hook_anchor) != 1:
    raise SystemExit(f"GetClientRect declaration anchor count={text.count(hook_anchor)}, expected 1")
text = text.replace(hook_anchor, helper, 1)

# Leave GetClientRect virtualization exactly as the proven A2-S2.1 path. Instead,
# split WM_SIZE at CallWindowProc: Steam sees physical size, then Steam's downstream
# call to GTA is rewritten back to the logical DLSS render size.
client_rect_block = r'''DETOURS_DECL(GetClientRect);
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
callwindow_block = client_rect_block + r'''

// Steam's overlay can subclass the game window before b-bridge attaches. In that
// case the bridge's downstream WndProc is Steam's proc. We let Steam receive the
// physical presenter-sized WM_SIZE, then intercept Steam's CallWindowProcA/W when
// it forwards the message to GTA and restore the logical render dimensions there.
template<bool bUnicode>
static LRESULT WINAPI NewCallWindowProc(WNDPROC lpPrevWndFunc, HWND hWnd, UINT Msg,
                                        WPARAM wParam, LPARAM lParam) {
  LPARAM downstreamLParam = lParam;
  if (Msg == WM_SIZE && wParam != SIZE_MINIMIZED && M3kStackContainsSteamOverlay()) {
    M3kUiConfig config;
    if (M3kUiVirtualActive(hWnd, &config)) {
      downstreamLParam = MAKELPARAM(config.width, config.height);
      static uint32_t lastW = 0, lastH = 0;
      if (lastW != config.width || lastH != config.height) {
        Logger::info(format_string("[M3K-STEAM-V3] Steam downstream CallWindowProc rewrites WM_SIZE to logical %ux%u",
          config.width, config.height));
        lastW = config.width;
        lastH = config.height;
      }
    }
  }

  if constexpr (bUnicode) {
    return OrigCallWindowProcW(lpPrevWndFunc, hWnd, Msg, wParam, downstreamLParam);
  } else {
    return OrigCallWindowProcA(lpPrevWndFunc, hWnd, Msg, wParam, downstreamLParam);
  }
}
DETOURS_FUNC__UNICODE(CallWindowProc, NewCallWindowProc<true>, NewCallWindowProc<false>);
'''
if text.count(client_rect_block) != 1:
    raise SystemExit(f"GetClientRect wrapper block count={text.count(client_rect_block)}, expected 1")
text = text.replace(client_rect_block, callwindow_block, 1)

attach_old = "  bSuccess &= DETOURS_ATTACH__UNICODE(SetWindowLong);\n  bSuccess &= DETOURS_ATTACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_ATTACH(GetClientRect);\n  DetourTransactionCommit();\n"
attach_new = "  bSuccess &= DETOURS_ATTACH__UNICODE(SetWindowLong);\n  bSuccess &= DETOURS_ATTACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_ATTACH(GetClientRect);\n  bSuccess &= DETOURS_ATTACH__UNICODE(CallWindowProc);\n  DetourTransactionCommit();\n"
if text.count(attach_old) != 1:
    raise SystemExit(f"attach anchor count={text.count(attach_old)}, expected 1")
text = text.replace(attach_old, attach_new, 1)

detach_old = "  bSuccess &= DETOURS_DETACH__UNICODE(SetWindowLong);\n  bSuccess &= DETOURS_DETACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_DETACH(GetClientRect);\n  DetourTransactionCommit();\n"
detach_new = "  bSuccess &= DETOURS_DETACH__UNICODE(SetWindowLong);\n  bSuccess &= DETOURS_DETACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_DETACH(GetClientRect);\n  bSuccess &= DETOURS_DETACH__UNICODE(CallWindowProc);\n  DetourTransactionCommit();\n"
if text.count(detach_old) != 1:
    raise SystemExit(f"detach anchor count={text.count(detach_old)}, expected 1")
text = text.replace(detach_old, detach_new, 1)

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
    lresult = !isUnicode ? CallWindowProcA(g_gameWndProc, hWnd, msg, wParam, gameLParam) :
                           CallWindowProcW(g_gameWndProc, hWnd, msg, wParam, gameLParam);
'''
wnd_new = r'''    LPARAM gameLParam = lParam;
    M3kUiConfig config;
    if (msg == WM_SIZE && wParam != SIZE_MINIMIZED && M3kUiVirtualActive(hWnd, &config)) {
      const bool steamTop = M3kAddressBelongsToSteamOverlay(reinterpret_cast<const void*>(g_gameWndProc));
      if (steamTop && OrigGetClientRect) {
        RECT physicalRect = { };
        if (OrigGetClientRect(hWnd, &physicalRect)) {
          const LONG physicalW = physicalRect.right - physicalRect.left;
          const LONG physicalH = physicalRect.bottom - physicalRect.top;
          if (physicalW > 0 && physicalH > 0) {
            gameLParam = MAKELPARAM(UINT(physicalW), UINT(physicalH));
            static uint32_t lastPhysicalW = 0, lastPhysicalH = 0;
            if (lastPhysicalW != UINT(physicalW) || lastPhysicalH != UINT(physicalH) ||
                config.width != UINT(physicalW) || config.height != UINT(physicalH)) {
              Logger::info(format_string("[M3K-STEAM-V3] top Steam WndProc gets physical WM_SIZE %ux%u; logical GTA size %ux%u",
                UINT(physicalW), UINT(physicalH), config.width, config.height));
              lastPhysicalW = UINT(physicalW);
              lastPhysicalH = UINT(physicalH);
            }
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
    lresult = !isUnicode ? CallWindowProcA(g_gameWndProc, hWnd, msg, wParam, gameLParam) :
                           CallWindowProcW(g_gameWndProc, hWnd, msg, wParam, gameLParam);
'''
if text.count(wnd_old) != 1:
    raise SystemExit(f"WndProc forwarding anchor count={text.count(wnd_old)}, expected 1")
text = text.replace(wnd_old, wnd_new, 1)

for marker in (
    "[M3K-STEAM-V3]",
    "gameoverlayrenderer.dll",
    "M3kStackContainsSteamOverlay",
    "DETOURS_ATTACH__UNICODE(CallWindowProc)",
    "Steam downstream CallWindowProc rewrites WM_SIZE",
    "top Steam WndProc gets physical WM_SIZE",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"Public Steam overlay WM_SIZE split v3 applied: {source}")
