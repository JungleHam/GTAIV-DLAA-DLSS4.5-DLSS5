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
for old_marker in ("[M3K-STEAM]", "[M3K-STEAM-V2]", "[M3K-STEAM-V3]", "[M3K-STEAM-V4]"):
    if old_marker in text:
        raise SystemExit(f"Steam overlay hotfix already present ({old_marker}); apply v4 to clean frozen UI-patched bridge source")

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
helper = r'''static HMODULE M3kSteamOverlay32() {
  static HMODULE steam32 = nullptr;
  if (!steam32)
    steam32 = GetModuleHandleW(L"gameoverlayrenderer.dll");
  return steam32;
}

static HMODULE M3kSteamOverlay64() {
  static HMODULE steam64 = nullptr;
  if (!steam64)
    steam64 = GetModuleHandleW(L"gameoverlayrenderer64.dll");
  return steam64;
}

static bool M3kSteamOverlayLoaded() {
  return M3kSteamOverlay32() != nullptr || M3kSteamOverlay64() != nullptr;
}

static bool M3kAddressBelongsToSteamOverlay(const void* address) {
  if (!address)
    return false;

  const HMODULE steam32 = M3kSteamOverlay32();
  const HMODULE steam64 = M3kSteamOverlay64();
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

// V4 learns the actual WndProc chain before changing what any component sees.
// This keeps the first/startup WM_SIZE on the already-proven logical path. Once
// Steam is observed forwarding a WM_SIZE through CallWindowProc, later messages
// can safely enter the downstream chain at physical presenter size and switch
// back to logical size exactly when Steam forwards to the next WndProc.
static bool g_m3kSteamChainConfirmed = false;
thread_local bool g_m3kSteamSplitActive = false;
thread_local bool g_m3kSteamLogicalInjected = false;

DETOURS_DECL(GetClientRect);
'''
if text.count(hook_anchor) != 1:
    raise SystemExit(f"GetClientRect declaration anchor count={text.count(hook_anchor)}, expected 1")
text = text.replace(hook_anchor, helper, 1)

# Keep GetClientRect virtualization on the proven A2-S2.1 path. The WM_SIZE split
# is performed at CallWindowProc after the Steam chain has been observed once.
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

// Observe Steam in the downstream WndProc chain. On the first observation we
// only learn the chain and leave the current message untouched. For subsequent
// split-active WM_SIZE messages, Steam receives the physical presenter extent;
// the first CallWindowProc made from Steam switches the message back to GTA's
// logical DLSS render extent, and all deeper calls stay logical.
template<bool bUnicode>
static LRESULT WINAPI NewCallWindowProc(WNDPROC lpPrevWndFunc, HWND hWnd, UINT Msg,
                                        WPARAM wParam, LPARAM lParam) {
  LPARAM downstreamLParam = lParam;
  const bool relevantSize = Msg == WM_SIZE && wParam != SIZE_MINIMIZED && hWnd == g_hwnd;
  const bool steamInStack = relevantSize && M3kStackContainsSteamOverlay();

  if (steamInStack && !g_m3kSteamChainConfirmed) {
    g_m3kSteamChainConfirmed = true;
    Logger::info(format_string("[M3K-STEAM-V4] Steam WM_SIZE chain confirmed; future size messages may split physical->Steam->logical GTA"));
  }

  if (relevantSize && g_m3kSteamSplitActive) {
    M3kUiConfig config;
    if (M3kUiVirtualActive(hWnd, &config)) {
      if (steamInStack && !g_m3kSteamLogicalInjected) {
        g_m3kSteamLogicalInjected = true;
        downstreamLParam = MAKELPARAM(config.width, config.height);
        Logger::info(format_string("[M3K-STEAM-V4] Steam saw physical WM_SIZE; downstream GTA chain switched to logical %ux%u",
          config.width, config.height));
      } else if (g_m3kSteamLogicalInjected) {
        downstreamLParam = MAKELPARAM(config.width, config.height);
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
    bool steamSplit = false;
    if (msg == WM_SIZE && wParam != SIZE_MINIMIZED && M3kUiVirtualActive(hWnd, &config)) {
      // Do not attempt the split until we have actually observed Steam forwarding
      // WM_SIZE in this process. This preserves the known-good startup behavior.
      if (g_m3kSteamChainConfirmed && M3kSteamOverlayLoaded() && OrigGetClientRect) {
        RECT physicalRect = { };
        if (OrigGetClientRect(hWnd, &physicalRect)) {
          const LONG physicalW = physicalRect.right - physicalRect.left;
          const LONG physicalH = physicalRect.bottom - physicalRect.top;
          if (physicalW > 0 && physicalH > 0) {
            gameLParam = MAKELPARAM(UINT(physicalW), UINT(physicalH));
            steamSplit = true;
            g_m3kSteamSplitActive = true;
            g_m3kSteamLogicalInjected = false;
            Logger::info(format_string("[M3K-STEAM-V4] entering downstream WndProc chain with physical WM_SIZE %ux%u; GTA logical target %ux%u",
              UINT(physicalW), UINT(physicalH), config.width, config.height));
          }
        }
      }

      if (!steamSplit) {
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

    if (steamSplit) {
      if (!g_m3kSteamLogicalInjected) {
        Logger::warn(format_string("[M3K-STEAM-V4] physical WM_SIZE entered chain but Steam did not forward through the detected CallWindowProc path"));
      }
      g_m3kSteamSplitActive = false;
      g_m3kSteamLogicalInjected = false;
    }
'''
if text.count(wnd_old) != 1:
    raise SystemExit(f"WndProc forwarding anchor count={text.count(wnd_old)}, expected 1")
text = text.replace(wnd_old, wnd_new, 1)

for marker in (
    "[M3K-STEAM-V4]",
    "Steam WM_SIZE chain confirmed",
    "entering downstream WndProc chain with physical WM_SIZE",
    "Steam saw physical WM_SIZE; downstream GTA chain switched to logical",
    "g_m3kSteamChainConfirmed",
    "g_m3kSteamSplitActive",
    "DETOURS_ATTACH__UNICODE(CallWindowProc)",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"Public Steam overlay learned WM_SIZE split v4 applied: {source}")
