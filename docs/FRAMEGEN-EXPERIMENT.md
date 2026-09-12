# Experimental DLSS Frame Generation track

> Branch: `framegen-experimental`. This work is intentionally isolated from the known-good main installer.

## Goal

Extend the verified GTA IV path from:

```text
GTA IV -> b-bridge/DXVK -> ReShade/Lumenite -> DLAA -> optional DFC DLSS5 Neural Rendering -> Present
```

toward:

```text
GTA IV -> b-bridge/DXVK -> ReShade/Lumenite -> DLAA -> optional DFC DLSS5 Neural Rendering -> DLSS Frame Generation -> Present
```

The design uses NVIDIA's open-source RTX Remix / dxvk-remix DLFG implementation as the reference rather than transplanting the whole RTX Remix renderer.

## Why this is plausible

RTX Remix's open source DLFG path already implements:

- NGX DLSS-G feature creation/evaluation on Vulkan;
- color + screen-space motion-vector + depth inputs;
- current/previous camera matrices;
- a dedicated DLFG presenter;
- swapchain enlargement for interpolated frames;
- queue/semaphore/fence synchronization;
- pacing and multi-frame interpolation controls.

Our existing GTA IV stack already produces resolved color, Lumenite screen-space motion vectors and depth in the 64-bit `NvRemixBridge.exe` process. The remaining difficult pieces are camera/state reconstruction and safe presentation/pacing.

## Milestones

### M1 — capability + feature-create probe

Status: **implemented on this branch; hardware test pending.**

`tools/dlfg-poc/` builds a ReShade x64 add-on that loads inside `NvRemixBridge.exe`, creates a private Vulkan device on the NVIDIA GPU, initializes NGX, checks `FrameGeneration.Available`, queries `MultiFrameCountMax`, attempts `NGX_VK_CREATE_DLSSG`, logs the result, then cleans up. It never presents a generated frame.

Acceptance line:

```text
SUCCESS: NVIDIA NGX DLSS Frame Generation feature was created on the RTX GPU.
```

### M2 — off-screen interpolation

Feed one real resolved frame plus Lumenite MV/depth into DLSS-G and successfully evaluate an interpolated image into a private/off-screen Vulkan image. Still no additional presentation.

### M3 — stable 2x presentation

Implement a dedicated presenter/pacer so the display cadence is:

```text
real N -> generated N+0.5 -> real N+1
```

Start with CPU pacing, one generated frame, borderless/windowed mode and no DFC.

### M4 — DFC integration

Move the FG color source after DFC's final neural output and validate:

```text
DLAA -> DLSS5 Neural Rendering -> DLSS Frame Generation 2x
```

Only after this is stable should 3x/4x multi-frame generation be investigated.

## Current guide quality observation

The Feeder probes can legitimately show zero motion in static scenes. During actual movement the same setup has produced non-zero Lumenite vectors with useful varying depth. Future milestones must still add stronger whole-frame validation and reset/history handling before relying on those guides for presentation-quality FG.

## Non-goals during early milestones

- no path tracing;
- no complete RTX Remix runtime replacement;
- no modifications to the main release installer;
- no 3x/4x MFG before 2x is stable;
- no claim that generated-frame quality is solved merely because the NGX feature can be created.
