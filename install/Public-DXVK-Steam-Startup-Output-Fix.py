#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-DXVK-Steam-Startup-Output-Fix.py <dxvk-root>")

root = Path(sys.argv[1])
source = root / "src" / "d3d9" / "d3d9_swapchain.cpp"
if not source.is_file():
    raise SystemExit(f"missing DXVK source: {source}")

text = source.read_text(encoding="utf-8")
if "[M3K-S1B] config" not in text or "M3kScheduleAutoResize" not in text:
    raise SystemExit("A2-S1B presenter patch must be applied first")
if "[M3K-STEAM-PRESENTER] startup output prime" in text:
    print("Steam presenter startup output fix already present")
    raise SystemExit(0)

# Add a synchronous one-shot startup resize helper. This is intentionally separate
# from the existing async Present-time resize so the very first presenter/window
# extent can already be the physical output size when Steam initializes its overlay.
anchor = r'''  static void M3kScheduleAutoResize(HWND window, BOOL windowed) {
'''
pos = text.find(anchor)
if pos < 0:
    raise SystemExit("M3kScheduleAutoResize anchor missing")

# Insert helper immediately before the existing async function.
helper = r'''  static void M3kPrimeOutputWindow(HWND window, BOOL windowed) {
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

    RECT client = { }, outer = { };
    POINT clientOrigin = { 0, 0 };
    if (!GetClientRect(window, &client) ||
        !GetWindowRect(window, &outer) ||
        !ClientToScreen(window, &clientOrigin))
      return;

    const int clientW = client.right - client.left;
    const int clientH = client.bottom - client.top;
    const int outerW = outer.right - outer.left;
    const int outerH = outer.bottom - outer.top;
    const int leftInset = clientOrigin.x - outer.left;
    const int topInset = clientOrigin.y - outer.top;
    const int borderW = outerW - clientW;
    const int borderH = outerH - clientH;

    if (uint32_t(clientW) == desiredW && uint32_t(clientH) == desiredH &&
        clientOrigin.x == monitorInfo.rcMonitor.left && clientOrigin.y == monitorInfo.rcMonitor.top) {
      Logger::info(str::format(
        "[M3K-STEAM-PRESENTER] startup output prime already ", desiredW, "x", desiredH));
      return;
    }

    Logger::info(str::format(
      "[M3K-STEAM-PRESENTER] startup output prime ",
      clientW, "x", clientH, " -> ", desiredW, "x", desiredH,
      " before UpdateWindowCtx"));

    SetWindowPos(
      window, nullptr,
      monitorInfo.rcMonitor.left - leftInset,
      monitorInfo.rcMonitor.top - topInset,
      int(desiredW) + borderW,
      int(desiredH) + borderH,
      SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }

'''
text = text[:pos] + helper + text[pos:]

ctor_old = r'''    m_presentParams = *pPresentParams;
    m_window = m_presentParams.hDeviceWindow;

    UpdateWindowCtx();
'''
ctor_new = r'''    m_presentParams = *pPresentParams;
    m_window = m_presentParams.hDeviceWindow;

#ifdef _WIN32
    M3kPrimeOutputWindow(m_window, m_presentParams.Windowed);
#endif

    UpdateWindowCtx();
'''
if text.count(ctor_old) != 1:
    raise SystemExit(f"swapchain constructor anchor count={text.count(ctor_old)}, expected 1")
text = text.replace(ctor_old, ctor_new, 1)

for marker in (
    "[M3K-STEAM-PRESENTER] startup output prime",
    "M3kPrimeOutputWindow(m_window, m_presentParams.Windowed);",
    "M3kScheduleAutoResize(window, m_presentParams.Windowed);",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"Steam presenter startup output fix applied: {source}")
