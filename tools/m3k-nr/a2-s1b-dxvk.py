#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: a2-s1b-dxvk.py <dxvk-root>")

root = Path(sys.argv[1])
source = root / "src" / "d3d9" / "d3d9_swapchain.cpp"
if not source.is_file():
    raise SystemExit(f"missing DXVK source: {source}")

text = source.read_text(encoding="utf-8")
if "M3K_QueryPresentSourceV1" not in text:
    raise SystemExit("M3K source tap is missing; apply dxvk-v3.0.2-m3k-source-tap.patch first")
if "[M3K-S1B] config" in text:
    print("A2-S1B patch already present")
    raise SystemExit(0)

helper_anchor = "namespace dxvk {\n\n  static uint16_t MapGammaControlPoint(float x) {\n"
helper = r'''namespace dxvk {

#ifdef _WIN32
  // A2-S1B: decouple GTA's D3D9 render extent from the actual presenter/window extent.
  // Settings live next to d3d9vk_x64.dll in .trex\m3k-nr.ini so DXVK and the Feeder
  // consume the same requested render/output split.
  struct M3kResolutionConfig {
    uint32_t renderWidth = 0;
    uint32_t renderHeight = 0;
    uint32_t outputWidth = 0;
    uint32_t outputHeight = 0;
    bool autoResize = false;
  };

  static int g_m3kResolutionAnchor = 0;
  static volatile LONG g_m3kResizePending = 0;

  static bool M3kResolutionConfigPath(wchar_t* path, size_t pathCount) {
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCWSTR>(&g_m3kResolutionAnchor), &module))
      return false;

    DWORD length = GetModuleFileNameW(module, path, DWORD(pathCount));
    if (!length || length >= pathCount)
      return false;

    wchar_t* slash = wcsrchr(path, L'\\');
    if (!slash)
      return false;

    static const wchar_t name[] = L"m3k-nr.ini";
    const size_t prefix = size_t(slash + 1 - path);
    if (prefix + (sizeof(name) / sizeof(name[0])) > pathCount)
      return false;

    lstrcpyW(slash + 1, name);
    return true;
  }

  static M3kResolutionConfig M3kGetResolutionConfig() {
    static M3kResolutionConfig config;
    static M3kResolutionConfig last;
    static ULONGLONG nextPoll = 0;
    static bool first = true;

    const ULONGLONG now = GetTickCount64();
    if (now < nextPoll)
      return config;
    nextPoll = now + 1000;

    wchar_t path[MAX_PATH] = { };
    M3kResolutionConfig next;
    if (M3kResolutionConfigPath(path, MAX_PATH)) {
      next.renderWidth  = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
      next.renderHeight = GetPrivateProfileIntW(L"M3K", L"RenderHeight", 0, path);
      next.outputWidth  = GetPrivateProfileIntW(L"M3K", L"OutputWidth", 0, path);
      next.outputHeight = GetPrivateProfileIntW(L"M3K", L"OutputHeight", 0, path);
      next.autoResize   = GetPrivateProfileIntW(L"M3K", L"AutoResizeWindow", 0, path) != 0;
    }

    const bool changed =
      next.renderWidth  != last.renderWidth  || next.renderHeight != last.renderHeight ||
      next.outputWidth  != last.outputWidth  || next.outputHeight != last.outputHeight ||
      next.autoResize   != last.autoResize;

    config = next;
    if (first || changed) {
      Logger::info(str::format(
        "[M3K-S1B] config render=", config.renderWidth, "x", config.renderHeight,
        " output=", config.outputWidth, "x", config.outputHeight,
        " (0=monitor) autoResize=", config.autoResize ? 1 : 0));
      last = config;
      first = false;
    }
    return config;
  }

  static void M3kApplyRenderOverride(D3DPRESENT_PARAMETERS* params) {
    if (!params || !params->Windowed)
      return;

    const auto config = M3kGetResolutionConfig();
    if (!config.renderWidth || !config.renderHeight)
      return;

    if (params->BackBufferWidth != config.renderWidth ||
        params->BackBufferHeight != config.renderHeight) {
      Logger::info(str::format(
        "[M3K-S1B] D3D9 backbuffer override ",
        params->BackBufferWidth, "x", params->BackBufferHeight,
        " -> ", config.renderWidth, "x", config.renderHeight));
    }

    params->BackBufferWidth = config.renderWidth;
    params->BackBufferHeight = config.renderHeight;
  }

  struct M3kResizeJob {
    HWND window;
    uint32_t width;
    uint32_t height;
    RECT monitorRect;
  };

  static DWORD WINAPI M3kResizeWorker(void* opaque) {
    M3kResizeJob* job = static_cast<M3kResizeJob*>(opaque);
    if (job && IsWindow(job->window)) {
      RECT client = { }, outer = { };
      POINT clientOrigin = { 0, 0 };

      if (GetClientRect(job->window, &client) &&
          GetWindowRect(job->window, &outer) &&
          ClientToScreen(job->window, &clientOrigin)) {
        const int clientW = client.right - client.left;
        const int clientH = client.bottom - client.top;
        const int outerW = outer.right - outer.left;
        const int outerH = outer.bottom - outer.top;
        const int leftInset = clientOrigin.x - outer.left;
        const int topInset = clientOrigin.y - outer.top;
        const int borderW = outerW - clientW;
        const int borderH = outerH - clientH;

        SetWindowPos(
          job->window, nullptr,
          job->monitorRect.left - leftInset,
          job->monitorRect.top - topInset,
          int(job->width) + borderW,
          int(job->height) + borderH,
          SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
      }
    }

    if (job)
      HeapFree(GetProcessHeap(), 0, job);
    InterlockedExchange(&g_m3kResizePending, 0);
    return 0;
  }

  static void M3kScheduleAutoResize(HWND window, BOOL windowed) {
    if (!window || !windowed)
      return;

    const auto config = M3kGetResolutionConfig();
    if (!config.autoResize)
      return;

    HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitorInfo = { };
    monitorInfo.cbSize = sizeof(monitorInfo);
    if (!monitor || !GetMonitorInfoW(monitor, &monitorInfo))
      return;

    const uint32_t monitorW = uint32_t(monitorInfo.rcMonitor.right - monitorInfo.rcMonitor.left);
    const uint32_t monitorH = uint32_t(monitorInfo.rcMonitor.bottom - monitorInfo.rcMonitor.top);
    const uint32_t desiredW = config.outputWidth  ? config.outputWidth  : monitorW;
    const uint32_t desiredH = config.outputHeight ? config.outputHeight : monitorH;
    if (!desiredW || !desiredH)
      return;

    RECT client = { };
    POINT origin = { 0, 0 };
    if (!GetClientRect(window, &client) || !ClientToScreen(window, &origin))
      return;

    const uint32_t currentW = uint32_t(client.right - client.left);
    const uint32_t currentH = uint32_t(client.bottom - client.top);
    if (currentW == desiredW && currentH == desiredH &&
        origin.x == monitorInfo.rcMonitor.left && origin.y == monitorInfo.rcMonitor.top)
      return;

    if (InterlockedCompareExchange(&g_m3kResizePending, 1, 0) != 0)
      return;

    auto* job = static_cast<M3kResizeJob*>(
      HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(M3kResizeJob)));
    if (!job) {
      InterlockedExchange(&g_m3kResizePending, 0);
      return;
    }

    job->window = window;
    job->width = desiredW;
    job->height = desiredH;
    job->monitorRect = monitorInfo.rcMonitor;

    Logger::info(str::format(
      "[M3K-S1B] scheduling window client ",
      currentW, "x", currentH, " -> ", desiredW, "x", desiredH,
      " (monitor ", monitorW, "x", monitorH, ")"));

    HANDLE thread = CreateThread(nullptr, 0, M3kResizeWorker, job, 0, nullptr);
    if (!thread) {
      HeapFree(GetProcessHeap(), 0, job);
      InterlockedExchange(&g_m3kResizePending, 0);
      return;
    }
    CloseHandle(thread);
  }
#endif

  static uint16_t MapGammaControlPoint(float x) {
'''

if text.count(helper_anchor) != 1:
    raise SystemExit(f"helper anchor count = {text.count(helper_anchor)}, expected 1")
text = text.replace(helper_anchor, helper, 1)

present_old = """    if (m_window != window) {\n      m_window = window;\n      m_displayRefreshRateDirty = true;\n    }\n\n    if (!UpdateWindowCtx())\n"""
present_new = """    if (m_window != window) {\n      m_window = window;\n      m_displayRefreshRateDirty = true;\n    }\n\n#ifdef _WIN32\n    M3kScheduleAutoResize(window, m_presentParams.Windowed);\n#endif\n\n    if (!UpdateWindowCtx())\n"""
if text.count(present_old) != 1:
    raise SystemExit(f"Present anchor count = {text.count(present_old)}, expected 1")
text = text.replace(present_old, present_new, 1)

start_marker = "  void D3D9SwapChainEx::NormalizePresentParameters(D3DPRESENT_PARAMETERS* pPresentParams) {"
next_marker = "  void D3D9SwapChainEx::PresentImage"
start = text.find(start_marker)
if start < 0:
    raise SystemExit("NormalizePresentParameters start not found")
next_fn = text.find(next_marker, start)
if next_fn < 0:
    raise SystemExit("PresentImage boundary after NormalizePresentParameters not found")
segment = text[start:next_fn]
close = segment.rfind("\n  }\n")
if close < 0:
    raise SystemExit("NormalizePresentParameters closing brace not found")
insert_at = start + close
render_call = "\n\n#ifdef _WIN32\n    M3kApplyRenderOverride(pPresentParams);\n#endif"
text = text[:insert_at] + render_call + text[insert_at:]

for marker in (
    "[M3K-S1B] config",
    "M3kApplyRenderOverride(pPresentParams);",
    "M3kScheduleAutoResize(window, m_presentParams.Windowed);",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"A2-S1B DXVK patch applied: {source}")
