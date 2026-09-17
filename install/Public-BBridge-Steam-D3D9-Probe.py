#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-Steam-D3D9-Probe.py <b-bridge-root>")

root = Path(sys.argv[1])
client = root / "src" / "client"
files = {
    "device": client / "d3d9_device.cpp",
    "swapchain": client / "d3d9_swapchain.cpp",
    "surface": client / "d3d9_surface.cpp",
}
for name, path in files.items():
    if not path.is_file():
        raise SystemExit(f"missing b-bridge source ({name}): {path}")

header = client / "m3k_steam_probe.h"
if header.exists():
    raise SystemExit(f"probe header already exists: {header}")

header.write_text(r'''#pragma once

// M3K Steam overlay D3D9 sizing probe. Diagnostic only: this never changes
// any D3D9 value. It only identifies calls whose stack contains Steam's
// overlay module so we can learn which size source Steam actually consumes.
static inline bool M3kSteamProbeAddressBelongsToOverlay(const void* address) {
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
                          reinterpret_cast<LPCWSTR>(address), &actual) || !actual) {
    return false;
  }
  return (steam32 && actual == steam32) || (steam64 && actual == steam64);
}

static inline bool M3kSteamProbeStackContainsOverlay() {
  void* frames[32] = { };
  const USHORT count = CaptureStackBackTrace(1, 32, frames, nullptr);
  for (USHORT i = 0; i < count; ++i) {
    if (M3kSteamProbeAddressBelongsToOverlay(frames[i]))
      return true;
  }
  return false;
}
''', encoding="utf-8", newline="\n")

# Add the helper to the three translation units.
for key in ("device", "swapchain", "surface"):
    path = files[key]
    text = path.read_text(encoding="utf-8")
    if "[M3K-STEAM-D3D]" in text or '"m3k_steam_probe.h"' in text:
        raise SystemExit(f"Steam D3D9 probe already present in {path}")
    anchor = '#include "pch.h"\n'
    if text.count(anchor) != 1:
        raise SystemExit(f"pch include anchor count={text.count(anchor)} in {path}, expected 1")
    text = text.replace(anchor, anchor + '#include "m3k_steam_probe.h"\n', 1)
    path.write_text(text, encoding="utf-8", newline="\n")

# ---- Device: GetDisplayMode -------------------------------------------------
path = files["device"]
text = path.read_text(encoding="utf-8")
old = r'''  DeviceBridge::pop_front();
  return hresult;
}

template<bool EnableSync>
HRESULT Direct3DDevice9Ex_LSS<EnableSync>::GetCreationParameters'''
new = r'''  DeviceBridge::pop_front();
  if (SUCCEEDED(hresult) && pMode) {
    static unsigned m3kLogCount = 0;
    const bool steam = M3kSteamProbeStackContainsOverlay();
    if (steam || m3kLogCount < 6) {
      Logger::info(format_string("[M3K-STEAM-D3D] Device::GetDisplayMode steam=%u -> %ux%u @%uHz fmt=%u",
        steam ? 1u : 0u, pMode->Width, pMode->Height, pMode->RefreshRate, UINT(pMode->Format)));
      ++m3kLogCount;
    }
  }
  return hresult;
}

template<bool EnableSync>
HRESULT Direct3DDevice9Ex_LSS<EnableSync>::GetCreationParameters'''
if text.count(old) != 1:
    raise SystemExit(f"GetDisplayMode tail anchor count={text.count(old)}, expected 1")
text = text.replace(old, new, 1)

# ---- Device: SetViewport ----------------------------------------------------
old = r'''  if (pViewport == nullptr) {
    return D3DERR_INVALIDCALL;
  }

  UID currentUID = 0;
  {
    {
      BRIDGE_DEVICE_LOCKGUARD();'''
new = r'''  if (pViewport == nullptr) {
    return D3DERR_INVALIDCALL;
  }

  if (M3kSteamProbeStackContainsOverlay()) {
    static unsigned m3kSteamSetViewportCount = 0;
    if (m3kSteamSetViewportCount < 16) {
      Logger::info(format_string("[M3K-STEAM-D3D] Device::SetViewport steam=1 -> xy=%u,%u size=%ux%u z=%g..%g",
        pViewport->X, pViewport->Y, pViewport->Width, pViewport->Height,
        double(pViewport->MinZ), double(pViewport->MaxZ)));
      ++m3kSteamSetViewportCount;
    }
  }

  UID currentUID = 0;
  {
    {
      BRIDGE_DEVICE_LOCKGUARD();'''
# There are several pointer/null/UID blocks in this file, so constrain replacement
# to the SetViewport function region.
setpos = text.find('HRESULT Direct3DDevice9Ex_LSS<EnableSync>::SetViewport(')
getpos = text.find('HRESULT Direct3DDevice9Ex_LSS<EnableSync>::GetViewport(', setpos)
if setpos < 0 or getpos < 0:
    raise SystemExit("Set/GetViewport function anchors missing")
region = text[setpos:getpos]
if region.count(old) != 1:
    raise SystemExit(f"SetViewport local anchor count={region.count(old)}, expected 1")
region = region.replace(old, new, 1)
text = text[:setpos] + region + text[getpos:]

# ---- Device: GetViewport ----------------------------------------------------
old = r'''  {
    BRIDGE_DEVICE_LOCKGUARD();
    *pViewport = m_state.viewport;
  }
  return S_OK;
}

template<bool EnableSync>
HRESULT Direct3DDevice9Ex_LSS<EnableSync>::SetMaterial'''
new = r'''  {
    BRIDGE_DEVICE_LOCKGUARD();
    *pViewport = m_state.viewport;
  }
  {
    static unsigned m3kLogCount = 0;
    const bool steam = M3kSteamProbeStackContainsOverlay();
    if (steam || m3kLogCount < 6) {
      Logger::info(format_string("[M3K-STEAM-D3D] Device::GetViewport steam=%u -> xy=%u,%u size=%ux%u z=%g..%g",
        steam ? 1u : 0u, pViewport->X, pViewport->Y, pViewport->Width, pViewport->Height,
        double(pViewport->MinZ), double(pViewport->MaxZ)));
      ++m3kLogCount;
    }
  }
  return S_OK;
}

template<bool EnableSync>
HRESULT Direct3DDevice9Ex_LSS<EnableSync>::SetMaterial'''
if text.count(old) != 1:
    raise SystemExit(f"GetViewport tail anchor count={text.count(old)}, expected 1")
text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8", newline="\n")

# ---- Swapchain --------------------------------------------------------------
path = files["swapchain"]
text = path.read_text(encoding="utf-8")

# Present: first few calls tell us whether Steam wraps the actual Present path.
old = r'''  ZoneScoped;
  LogFunctionCall();
#ifdef ENABLE_PRESENT_SEMAPHORE_TRACE'''
new = r'''  ZoneScoped;
  LogFunctionCall();
  {
    static unsigned m3kPresentCount = 0;
    if (m3kPresentCount < 6) {
      const bool steam = M3kSteamProbeStackContainsOverlay();
      Logger::info(format_string("[M3K-STEAM-D3D] SwapChain::Present steam=%u pres=%ux%u src=%s dst=%s",
        steam ? 1u : 0u, m_presParam.BackBufferWidth, m_presParam.BackBufferHeight,
        pSourceRect ? "rect" : "null", pDestRect ? "rect" : "null"));
      ++m3kPresentCount;
    }
  }
#ifdef ENABLE_PRESENT_SEMAPHORE_TRACE'''
if text.count(old) != 1:
    raise SystemExit(f"Present probe anchor count={text.count(old)}, expected 1")
text = text.replace(old, new, 1)

# GetBackBuffer: log even cached hits, because Steam commonly discovers the canvas this way.
old = r'''  if (ppBackBuffer == nullptr) {
    return D3DERR_INVALIDCALL;
  }

  if (auto surface = getChild(iBackBuffer)) {'''
new = r'''  if (ppBackBuffer == nullptr) {
    return D3DERR_INVALIDCALL;
  }

  {
    static unsigned m3kLogCount = 0;
    const bool steam = M3kSteamProbeStackContainsOverlay();
    if (steam || m3kLogCount < 8) {
      Logger::info(format_string("[M3K-STEAM-D3D] SwapChain::GetBackBuffer steam=%u index=%u pres=%ux%u",
        steam ? 1u : 0u, iBackBuffer, m_presParam.BackBufferWidth, m_presParam.BackBufferHeight));
      ++m3kLogCount;
    }
  }

  if (auto surface = getChild(iBackBuffer)) {'''
if text.count(old) != 1:
    raise SystemExit(f"GetBackBuffer probe anchor count={text.count(old)}, expected 1")
text = text.replace(old, new, 1)

# GetPresentParameters: prime suspect for Steam canvas dimensions.
old = r'''  *pPresentationParameters = m_presParam;
  return D3D_OK;
}'''
new = r'''  *pPresentationParameters = m_presParam;
  {
    static unsigned m3kLogCount = 0;
    const bool steam = M3kSteamProbeStackContainsOverlay();
    if (steam || m3kLogCount < 8) {
      Logger::info(format_string("[M3K-STEAM-D3D] SwapChain::GetPresentParameters steam=%u -> %ux%u windowed=%u hwnd=0x%p",
        steam ? 1u : 0u, pPresentationParameters->BackBufferWidth, pPresentationParameters->BackBufferHeight,
        pPresentationParameters->Windowed ? 1u : 0u, pPresentationParameters->hDeviceWindow));
      ++m3kLogCount;
    }
  }
  return D3D_OK;
}'''
# Restrict to final function to avoid another identical return elsewhere.
gppos = text.find('HRESULT Direct3DSwapChain9_LSS::GetPresentParameters(')
if gppos < 0:
    raise SystemExit("GetPresentParameters function anchor missing")
region = text[gppos:]
if region.count(old) != 1:
    raise SystemExit(f"GetPresentParameters local anchor count={region.count(old)}, expected 1")
region = region.replace(old, new, 1)
text = text[:gppos] + region
path.write_text(text, encoding="utf-8", newline="\n")

# ---- Surface::GetDesc -------------------------------------------------------
path = files["surface"]
text = path.read_text(encoding="utf-8")
old = r'''  (*pDesc) = m_desc;

  if (GlobalOptions::getSendReadOnlyCalls()) {'''
new = r'''  (*pDesc) = m_desc;
  {
    static unsigned m3kLogCount = 0;
    const bool steam = M3kSteamProbeStackContainsOverlay();
    if (steam || m3kLogCount < 12) {
      Logger::info(format_string("[M3K-STEAM-D3D] Surface::GetDesc steam=%u backbuffer=%u -> %ux%u fmt=%u usage=0x%x",
        steam ? 1u : 0u, m_isBackBuffer ? 1u : 0u, pDesc->Width, pDesc->Height,
        UINT(pDesc->Format), UINT(pDesc->Usage)));
      ++m3kLogCount;
    }
  }

  if (GlobalOptions::getSendReadOnlyCalls()) {'''
if text.count(old) != 1:
    raise SystemExit(f"Surface::GetDesc probe anchor count={text.count(old)}, expected 1")
text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8", newline="\n")

# Final verification.
combined = "\n".join(p.read_text(encoding="utf-8") for p in files.values())
for marker in (
    '[M3K-STEAM-D3D] Device::GetDisplayMode',
    '[M3K-STEAM-D3D] Device::SetViewport',
    '[M3K-STEAM-D3D] Device::GetViewport',
    '[M3K-STEAM-D3D] SwapChain::Present',
    '[M3K-STEAM-D3D] SwapChain::GetBackBuffer',
    '[M3K-STEAM-D3D] SwapChain::GetPresentParameters',
    '[M3K-STEAM-D3D] Surface::GetDesc',
):
    if marker not in combined:
        raise SystemExit(f"verification failed: {marker}")

print("Public Steam D3D9 sizing probe v5 applied")
