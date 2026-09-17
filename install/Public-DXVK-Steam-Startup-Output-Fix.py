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
if "[M3K-STEAM-PRESENTER-V2]" in text:
    print("Steam presenter startup output fix v2 already present")
    raise SystemExit(0)
if "[M3K-STEAM-PRESENTER] startup output prime" in text:
    raise SystemExit("rejected synchronous Steam presenter v1 patch is already present")

# V1 synchronously called SetWindowPos before UpdateWindowCtx(), which can re-enter
# the window/swapchain path while DXVK is only half-constructed. V2 deliberately
# reuses A2-S1B's already-working asynchronous resize worker and schedules it only
# after the swapchain constructor has finished its window context, backbuffers,
# blitter, gamma ramp and initial fullscreen/windowed setup.
ctor_tail = r'''    // Apply initial window mode and fullscreen state
    if (!m_presentParams.Windowed && FAILED(EnterFullscreenMode(pPresentParams, pFullscreenDisplayMode)))
      throw DxvkError("D3D9: Failed to set initial fullscreen state");
  }
'''
ctor_new = r'''    // Apply initial window mode and fullscreen state
    if (!m_presentParams.Windowed && FAILED(EnterFullscreenMode(pPresentParams, pFullscreenDisplayMode)))
      throw DxvkError("D3D9: Failed to set initial fullscreen state");

#ifdef _WIN32
    // Steam overlay startup sizing: prime the physical presenter window as soon as
    // the swapchain is fully initialized, but do it through the existing async
    // A2-S1B worker. Never call SetWindowPos synchronously from this constructor.
    Logger::info(str::format(
      "[M3K-STEAM-PRESENTER-V2] scheduling startup physical output after swapchain initialization"));
    M3kScheduleAutoResize(m_window, m_presentParams.Windowed);
#endif
  }
'''

if text.count(ctor_tail) != 1:
    raise SystemExit(f"swapchain constructor tail anchor count={text.count(ctor_tail)}, expected 1")
text = text.replace(ctor_tail, ctor_new, 1)

for marker in (
    "[M3K-STEAM-PRESENTER-V2] scheduling startup physical output after swapchain initialization",
    "M3kScheduleAutoResize(m_window, m_presentParams.Windowed);",
    "M3kScheduleAutoResize(window, m_presentParams.Windowed);",
):
    if marker not in text:
        raise SystemExit(f"verification failed: {marker}")

if "M3kPrimeOutputWindow" in text:
    raise SystemExit("rejected synchronous v1 helper leaked into v2 source")

source.write_text(text, encoding="utf-8", newline="\n")
print(f"Steam presenter startup output fix v2 applied: {source}")
