# Architecture

GTA IV remains a 32-bit Direct3D 9 application, while ReShade, NGX and the modern rendering stages run in the 64-bit b-bridge renderer process.

## Process / renderer split

```text
GTAIV.exe (32-bit)
  |
  | dinput8.dll
  +--> FusionFix
  |
  | d3d9.dll
  +--> A3-S2 b-bridge client
          |
          | IPC / bridge protocol
          v
      .trex\NvRemixBridge.exe (64-bit)
          |
          +--> .trex\d3d9vk_x64.dll
          |      -> Vulkan
          |
          +--> ReShade 6.8.0 x64
                  |
                  +--> LumeniteFX
                  |      -> depth + estimated motion vectors
                  |
                  +--> A3-S5 DLSS5-Feeder / M3K
                         |
                         +--> nvngx_dlss.dll 310.9.1
                         |      -> DLAA / DLSS 4.5 Super Resolution
                         |
                         +--> .trex\m3k\m3k-nvngx.dll
                         +--> .trex\m3k\nvngx_dlssnr.dll
                                -> NGX Feature 18 / DLSS 5 Neural Rendering
```

There is no Deep Fried Chicken stage in the current architecture.

## DLAA baseline

Step 2 establishes a native-resolution DLAA path:

```text
scene -> Lumenite depth/MV guides -> NGX DLAA -> output
```

The base DLAA install intentionally excludes the NR runtime so the known-good baseline can be verified before the combined module is added.

## DLSS 4.5 Super Resolution

Step 4 replaces the stock b-bridge client/Feeder path with the frozen A3-S2/A3-S5 integration.

A3-S2 keeps GTA's canonical shader constants unmodified and applies a complete c8-c11 projective WVP jitter only at the draw boundary. All four D3D9 draw paths are synchronized, and non-eligible draws restore the canonical unjittered WVP.

The bridge publishes the exact jitter sample through:

```text
Local\M3K_GTAIV_Jitter_v1
```

The Feeder consumes the same sample for DLSS. That coherent draw-boundary architecture fixed the earlier spatially inconsistent wobble and is the accepted temporal baseline.

## Startup prime

Cold-start low-resolution vibration was isolated to a narrow good source-resolution region rather than a DLSS quality-mode enum.

Known hardware observations:

```text
1472x828  -> vibration remains
1478x832  -> fixed
1485x835  -> fixed
1493x840  -> vibration remains
```

A3-S5 therefore starts each primed launch at `1485x835`, waits for 180 synchronized SR frames with the A3-S2 jitter handoff active, then releases to the saved SR profile and resets temporal history.

## Native DLSS 5 Neural Rendering

The combined module installs the tested NR runtime but leaves it disabled:

```ini
Mode=0
NRPasses=1
```

When the user enables `Mode=2`, the current production order is:

```text
true GTA source color
 -> native NGX Feature 18 / DLSS 5 NR
 -> DLSS 4.5 Super Resolution
 -> presenter resolution
```

Feature 18 is owned directly by the M3K/Feeder integration. NR and SR share the same source-size guide domain and synchronized temporal-jitter contract.

The tested configuration uses one NR pass. Multi-pass work existed during research, but the current user-facing module intentionally exposes the proven single-pass path.

## Motion vectors

GTA IV does not provide modern engine-native DLSS motion vectors. LumeniteFX supplies estimated motion vectors and depth through ReShade.

For SR, the guide textures are resized to the true source dimensions. The M3K adapter scales the motion-vector coordinate contract with the render/output ratio; this was audited and is intentionally retained.

## ReShade input patch

The swap chain references GTA's HWND, but ReShade runs in `NvRemixBridge.exe`. Stock ReShade therefore refuses normal input capture because the window belongs to another process.

b-bridge already transports DirectInput state through its old Remix message channel. The patch under `tools/reshade-bbridge-input/` reconnects that channel to ReShade's normal input system:

```text
GTA DirectInput
 -> b-bridge x86
 -> cross-process WM_* messages
 -> patched ReShade x64
 -> normal ReShade input / ImGui
```

It also sends `UWM_REMIX_UIACTIVE_MSG` back to GTA so clicks/keys are not consumed by both the overlay and the game.
