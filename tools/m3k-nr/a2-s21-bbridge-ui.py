#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: a2-s21-bbridge-ui.py <b-bridge-root>")

root = Path(sys.argv[1])
source = root / "src" / "client" / "window.cpp"
if not source.is_file():
    raise SystemExit(f"missing b-bridge source: {source}")

text = source.read_text(encoding="utf-8")
if "[M3K-UI] config" in text:
    print("A2-S2.1 UI virtualization patch already present")
    raise SystemExit(0)

include_anchor = "#include <unordered_map>\n#include <mutex>\n#include <d3d9.h>\n"
include_new = "#include <unordered_map>\n#include <mutex>\n#include <d3d9.h>\n"
if text.count(include_anchor) != 1:
    raise SystemExit(f"include anchor count={text.count(include_anchor)}, expected 1")
text = text.replace(include_anchor, include_new, 1)

globals_anchor = "HWND g_hwnd = nullptr;\nWNDPROC g_gameWndProc = nullptr;\nbool g_bActivateProcessed = false;\n"
globals_new = r'''HWND g_hwnd = nullptr;
WNDPROC g_gameWndProc = nullptr;
bool g_bActivateProcessed = false;

// M3K A2-S2.1: GTA IV computes HUD/menu coordinates from the physical client
// extent after the 64-bit S1B presenter resizes the HWND to 1440p. Keep the
// physical HWND at presenter size, but virtualize the game-facing client extent
// back to the true low render size. The 64-bit server is a separate process and
// therefore still observes the real 2560x1440 client.
struct M3kUiConfig {
  bool enabled = false;
  uint32_t width = 0;
  uint32_t height = 0;
};

static bool M3kUiConfigPath(wchar_t* path, size_t pathCount) {
  DWORD length = GetModuleFileNameW(nullptr, path, DWORD(pathCount));
  if (!length || length >= pathCount)
    return false;

  wchar_t* slash = wcsrchr(path, L'\\');
  if (!slash)
    return false;

  static const wchar_t suffix[] = L".trex\\m3k-nr.ini";
  const size_t prefix = size_t(slash + 1 - path);
  if (prefix + (sizeof(suffix) / sizeof(suffix[0])) > pathCount)
    return false;

  lstrcpyW(slash + 1, suffix);
  return true;
}

static M3kUiConfig M3kGetUiConfig() {
  static M3kUiConfig config;
  static M3kUiConfig last;
  static ULONGLONG nextPoll = 0;
  static bool first = true;

  const ULONGLONG now = GetTickCount64();
  if (now < nextPoll)
    return config;
  nextPoll = now + 1000;

  M3kUiConfig next;
  wchar_t path[MAX_PATH] = { };
  if (M3kUiConfigPath(path, MAX_PATH)) {
    next.enabled = GetPrivateProfileIntW(L"M3K", L"VirtualizeGameClient", 0, path) != 0;
    next.width = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
    next.height = GetPrivateProfileIntW(L"M3K", L"RenderHeight", 0, path);
  }

  const bool changed = next.enabled != last.enabled ||
                       next.width != last.width || next.height != last.height;
  config = next;
  if (first || changed) {
    Logger::info(format_string("[M3K-UI] config enabled=%d logicalClient=%ux%u",
      config.enabled ? 1 : 0, config.width, config.height));

    // M3K A2-S2.6 UI resync: the Feeder can post its logical WM_SIZE before this
    // 32-bit process notices the rewritten INI. If the true source reaches its
    // target quickly there may be no second Feeder retry, leaving GTA's HUD and
    // mouse state at the previous logical size while GetClientRect already
    // reports the new size. Whenever a live logical extent change is observed,
    // enqueue one fresh WM_SIZE from this process so the game WndProc consumes
    // the same dimensions that GetClientRect now exposes. PostMessage keeps this
    // asynchronous and does not physically resize the presenter-sized HWND.
    if (!first && changed && config.enabled && g_hwnd && g_gameWndProc &&
        config.width && config.height) {
      const BOOL posted = PostMessageW(g_hwnd, WM_SIZE, SIZE_RESTORED,
        MAKELPARAM(config.width, config.height));
      Logger::info(format_string("[M3K-UI] config-change resync WM_SIZE logical %ux%u posted=%d",
        config.width, config.height, posted ? 1 : 0));
    }

    last = config;
    first = false;
  }
  return config;
}

static bool M3kUiVirtualActive(HWND hWnd, M3kUiConfig* out = nullptr) {
  const auto config = M3kGetUiConfig();
  if (out)
    *out = config;
  return config.enabled && hWnd && hWnd == g_hwnd && config.width && config.height;
}
'''
if text.count(globals_anchor) != 1:
    raise SystemExit(f"globals anchor count={text.count(globals_anchor)}, expected 1")
text = text.replace(globals_anchor, globals_new, 1)

hook_anchor = "DETOURS_FUNC__UNICODE(GetWindowLong, NewGetWindowLong<true>, NewGetWindowLong<false>);\n\n\n/////////////////////////////////\n// Detours attaching/detaching //\n/////////////////////////////////\n"
hook_new = r'''DETOURS_FUNC__UNICODE(GetWindowLong, NewGetWindowLong<true>, NewGetWindowLong<false>);

// GetClientRect is process-local. Virtualizing it only in the 32-bit GTA process
// fixes HUD/menu layout without hiding the real presenter extent from the 64-bit
// NvRemixBridge/DXVK server.
DETOURS_DECL(GetClientRect);
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


/////////////////////////////////
// Detours attaching/detaching //
/////////////////////////////////
'''
if text.count(hook_anchor) != 1:
    raise SystemExit(f"hook anchor count={text.count(hook_anchor)}, expected 1")
text = text.replace(hook_anchor, hook_new, 1)

attach_old = "  bSuccess &= DETOURS_ATTACH__UNICODE(SetWindowLong);\n  bSuccess &= DETOURS_ATTACH__UNICODE(GetWindowLong);\n  DetourTransactionCommit();\n"
attach_new = "  bSuccess &= DETOURS_ATTACH__UNICODE(SetWindowLong);\n  bSuccess &= DETOURS_ATTACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_ATTACH(GetClientRect);\n  DetourTransactionCommit();\n"
if text.count(attach_old) != 1:
    raise SystemExit(f"attach anchor count={text.count(attach_old)}, expected 1")
text = text.replace(attach_old, attach_new, 1)

detach_old = "  bSuccess &= DETOURS_DETACH__UNICODE(SetWindowLong);\n  bSuccess &= DETOURS_DETACH__UNICODE(GetWindowLong);\n  DetourTransactionCommit();\n"
detach_new = "  bSuccess &= DETOURS_DETACH__UNICODE(SetWindowLong);\n  bSuccess &= DETOURS_DETACH__UNICODE(GetWindowLong);\n  bSuccess &= DETOURS_DETACH(GetClientRect);\n  DetourTransactionCommit();\n"
if text.count(detach_old) != 1:
    raise SystemExit(f"detach anchor count={text.count(detach_old)}, expected 1")
text = text.replace(detach_old, detach_new, 1)

wnd_old = r'''  const bool bSwallowMsg = remixMsg(hWnd, msg, wParam, lParam);
  if (bSwallowMsg) {
    lresult = !isUnicode ? DefWindowProcA(hWnd, msg, wParam, lParam) :
                           DefWindowProcW(hWnd, msg, wParam, lParam);
  } else {
    lresult = !isUnicode ? CallWindowProcA(g_gameWndProc, hWnd, msg, wParam, lParam) :
                           CallWindowProcW(g_gameWndProc, hWnd, msg, wParam, lParam);
  }
'''
wnd_new = r'''  const bool bSwallowMsg = remixMsg(hWnd, msg, wParam, lParam);
  if (bSwallowMsg) {
    lresult = !isUnicode ? DefWindowProcA(hWnd, msg, wParam, lParam) :
                           DefWindowProcW(hWnd, msg, wParam, lParam);
  } else {
    LPARAM gameLParam = lParam;
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
  }
'''
if text.count(wnd_old) != 1:
    raise SystemExit(f"WndProc forward anchor count={text.count(wnd_old)}, expected 1")
text = text.replace(wnd_old, wnd_new, 1)

for marker in (
    "[M3K-UI] config",
    "NewGetClientRect",
    "DETOURS_ATTACH(GetClientRect)",
    "forwarding WM_SIZE as logical",
    "config-change resync WM_SIZE logical",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"A2-S2.1 b-bridge UI virtualization patch applied: {source}")
