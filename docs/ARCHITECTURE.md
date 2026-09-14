# Architecture

For this branch's native **NR -> DLAA** experiment, see [M3K-NR.md](M3K-NR.md).
The historical optional DFC path described below is not used by M3K.

The unusual part of this setup is that GTA IV itself is still a 32-bit Direct3D 9 application, while the post-processing and NGX work occurs in a separate 64-bit process.

## Rendering path

```text
GTAIV.exe (32-bit)
  |
  | dinput8.dll
  +--> FusionFix ASI
  |
  | d3d9.dll
  +--> b-bridge client
          |
          | IPC / bridge protocol
          v
      .trex\NvRemixBridge.exe (64-bit)
          |
          +--> .trex\d3d9vk_x64.dll
          |      -> Vulkan
          |
          +--> ReShade 6.8.0 x64 Vulkan layer
                  |
                  +--> Lumenite_Kernel
                  |      -> estimated motion vectors + depth
                  |
                  +--> DLSS5-Feeder
                         -> nvngx_dlss.dll
                         -> NGX DLAA
                         |
                         +--> optional Deep Fried Chicken
                                -> nvngx_dlssnr.dll
                                -> NGX Feature 18 / Neural Rendering
```

The important consequence is that x64 ReShade add-ons, Feeder, DFC and the NGX DLLs belong next to `NvRemixBridge.exe` in `.trex`, **not** beside the 32-bit GTA executable as normal in-process DLLs.

## Why b-bridge is necessary

The working solution does not use ordinary in-process x86 DXVK for the complete pipeline. b-bridge transports the game's D3D9 work into a 64-bit server process, which gives ReShade and modern x64 NGX components a usable host.

The known-good b-bridge package bundles a non-RTX DXVK server path. A healthy bridge log identifies standard/non-RTX DXVK.

## DLAA guide data

GTA IV does not provide the modern guide buffers expected by DLSS. The setup therefore uses:

- depth exposed to ReShade;
- LumeniteFX Kernel as `DLSS5_MV_PROVIDER=3`;
- Feeder as the DLSS integration layer.

The motion vectors are estimated rather than engine-native. They have nevertheless been observed to produce valid, continuously changing motion-vector data and stable DLAA operation.

## Neural Rendering relationship to DLAA

DFC's successful log reports the neural input as the resolved output of the first DLAA pass. Therefore:

```text
DFC off:
scene -> DLAA -> output

DFC on:
scene -> DLAA -> DLSS 5 Neural Rendering -> output
```

The useful user-facing switch is **DLAA** versus **DLAA + Neural Rendering**.

## Why stock ReShade input fails

The rendered swap chain references GTA's window, but that window is owned by `GTAIV.exe`. ReShade is running in `NvRemixBridge.exe`.

Stock ReShade 6.8.0 checks the window owner before registering its normal input capture and rejects a HWND created by another process.

b-bridge, however, still contains the old RTX Remix cross-process input machinery:

```text
GTA DirectInput
 -> b-bridge converts DirectInput state to WM_* messages
 -> UWM_REMIX_BRIDGE_REGISTER_THREADPROC_MSG channel
 -> renderer-side thread
```

The original renderer-side consumer is absent when b-bridge is used with ordinary DXVK.

The patch in `tools/reshade-bbridge-input/` restores that consumer inside ReShade itself, routes the messages into ReShade's existing input object, and sends `UWM_REMIX_UIACTIVE_MSG` back to GTA so the game does not also consume clicks while the overlay is active.
