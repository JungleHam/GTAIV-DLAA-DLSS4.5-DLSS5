# Architecture

This page is the technical explanation of the project. The normal installation still has only four user-facing steps:

```text
1. FusionFix
2. DLAA
3. ReShade controls fix
4. DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering
```

Internal checkpoint names such as `A3-S2`, `A3-S5` and `M3K` are engineering/debug labels, not additional install stages.

## Why there is a bridge at all

GTA IV is a **32-bit Direct3D 9 game**, while the modern ReShade/NGX/DLSS work happens in a separate **64-bit renderer process**.

In simplified form:

```text
GTAIV.exe (32-bit)
  -> FusionFix
  -> bridge client
  -> NvRemixBridge.exe (64-bit)
  -> Vulkan / ReShade
  -> DLSS processing
  -> display
```

The exact technical chain is:

```text
GTAIV.exe
  |
  +--> FusionFix
  |
  +--> b-bridge client (d3d9.dll)
          |
          v
      .trex\NvRemixBridge.exe
          |
          +--> .trex\d3d9vk_x64.dll
          |      -> Vulkan
          |
          +--> ReShade 6.8.0
                  |
                  +--> LumeniteFX
                  |      -> estimated depth + motion data
                  |
                  +--> project DLSS integration
                         |
                         +--> nvngx_dlss.dll 310.9.1
                         |      -> DLAA / DLSS 4.5 Super Resolution
                         |
                         +--> .trex\m3k\m3k-nvngx.dll
                         +--> .trex\m3k\nvngx_dlssnr.dll
                                -> DLSS 5 Neural Rendering
```

## Step 2 — DLAA baseline

Step 2 establishes a native-resolution DLAA path:

```text
GTA IV at output resolution
 -> depth + estimated motion data
 -> NVIDIA DLAA
 -> display
```

This baseline is deliberately kept simple so it can be tested before resolution scaling and Neural Rendering are added.

## Step 4 — DLSS 4.5 Super Resolution

Step 4 lets GTA IV render internally below the final display resolution and then reconstructs the image with DLSS.

User-facing description:

```text
lower internal game resolution
 -> synchronized temporal data
 -> DLSS Super Resolution
 -> full display resolution
```

### Temporal synchronization

DLSS depends on tiny per-frame offsets plus previous-frame information. GTA IV was not designed to supply that modern temporal contract.

The project therefore keeps the game's geometry/raster offset and the DLSS jitter sample synchronized at draw time. It also restores the normal, unshifted state for draws that should not inherit that offset.

This fixed the severe spatially inconsistent wobble seen in earlier experiments.

Internal checkpoint name: **A3-S2**.

## Automatic startup stabilization

Cold-start testing found that very low DLSS render resolutions could begin a fresh session in a vibrating state.

The reliable sequence is:

```text
start at 1485×835
 -> hold synchronized temporal data for 180 frames
 -> switch automatically to the user's saved DLSS quality mode
```

Internal checkpoint name: **A3-S5**.

The name `startup prime` may still appear in logs/config because that is the original engineering term. User-facing documentation calls it **startup stabilization**.

## DLSS 5 Neural Rendering

Step 4 validates and installs the user-supplied Neural Rendering runtime but leaves it OFF by default. The project intentionally provides no direct NR runtime download link.

When enabled, the current rendering order is:

```text
GTA IV internal image
 -> DLSS 5 Neural Rendering
 -> DLSS 4.5 Super Resolution
 -> display/output resolution
```

The tested configuration uses one Neural Rendering pass.

In source code and logs you may see **Feature 18** or **NR18**. That is NVIDIA/NGX's internal feature identifier for the Neural Rendering stage; it is not another user-selectable module.

## The `M3K` name

`M3K` is the project's internal namespace for the custom DLSS integration code and configuration. For example:

```text
.trex\m3k-nr.ini
.trex\m3k\m3k-nvngx.dll
```

Users do not install an additional product called “M3K.” In the normal guide it is simply part of **Step 4 — DLSS 4.5 SR + DLSS 5 NR**.

## Motion vectors and depth

Modern temporal reconstruction needs information about how pixels moved between frames and where scene geometry sits in depth.

GTA IV does not expose modern engine-native DLSS motion vectors, so LumeniteFX estimates the motion/depth information through ReShade.

When Super Resolution is active, these guide textures are matched to the game's actual internal render resolution before DLSS uses them.

## ReShade controls fix

The game window belongs to `GTAIV.exe`, but ReShade runs in `NvRemixBridge.exe`. Stock ReShade therefore cannot normally capture input from GTA IV's window.

Step 3 reconnects that input path:

```text
GTA IV keyboard/mouse input
 -> 32-bit bridge
 -> cross-process Windows messages
 -> patched ReShade in the 64-bit renderer
```

That is why Home, mouse clicks and keyboard input work in the ReShade overlay after Step 3.

## Terminology reference

| Technical/internal wording | Plain-English meaning |
|---|---|
| `A3-S2` | temporal synchronization fix |
| `A3-S5` | automatic startup stabilization |
| `M3K` | project DLSS integration namespace |
| `Feature 18` / `NR18` | DLSS 5 Neural Rendering |
| `true source` | GTA IV's actual internal render resolution |
| `presenter` | final display/output resolution |
| `SRProfile` | saved DLSS Super Resolution quality mode |
| `UQ77` | Custom Ultra Quality at 77% render scale |
