# GTA IV FSR backend architecture

Status: **FSR-0 / implementation plan**  
Branch: `feature/fsr-3-1-5`  
Protected baseline: `main @ ed72c4ab301ed92763732577efa7eeaa8d3a3283`

## Version decision

The final target remains **FSR 3.1.5**, but AMD's current FidelityFX SDK 2.3 package does not currently provide a Vulkan backend.

For the first GTA IV Vulkan proof-of-life, use the last official Vulkan-capable SDK 1.x baseline:

- FidelityFX SDK tag: `v1.1.4`
- tag commit: `c6efa6bf7f2027b3ec94f28578bb5965eabb9e55`
- FSR upscaler version in that tag: **3.1.4**
- backend: **Vulkan**

FSR 3.1.5's documented upscaler delta from 3.1.4 is the RCAS negative-output fix. FSR-1 keeps sharpening disabled, so reconstruction plumbing can be proven against the official 3.1.4 Vulkan implementation first. Do not silently call the first candidate 3.1.5. Port/verify the 3.1.5 delta before the final backend is labelled 3.1.5.

## Placement

Do not put FSR in GTA IV's 32-bit D3D9 process and do not put it in the NVIDIA NR/D3D12 shim.

Add FSR beside the existing DLSS path in the **64-bit ReShade/Feeder Vulkan layer**.

```text
GTA IV D3D9
  -> b-bridge
  -> DXVK Vulkan presenter
       -> M3K_QueryPresentSourceV1
       -> shared GTA IV temporal/input layer
            +-> DLSS backend (existing, protected)
            +-> FSR backend (new)
  -> presentation
```

The current frozen M3K Vulkan adapter already exposes the critical resources at the correct point in the frame:

- real low-resolution DXVK source `VkImage`
- source `VkDevice` and image layout
- render width/height
- presenter/output width/height
- ReShade/Lumenite depth guide
- ReShade/Lumenite motion-vector guide
- current Vulkan command buffer
- bridge jitter state
- reconstruction history/reset plumbing

That is the narrowest integration point.

## Backend ownership

Create a dedicated FSR backend object with no NGX dependencies.

Suggested responsibility split:

```text
M3kSharedTemporalInputs
  color VkImage
  depth VkImage
  motion VkImage
  render/output sizes
  jitter
  reset
  frame time
  depth convention
  lifecycle gate
       |
       +-- M3kDlssBackend   (existing behavior)
       |
       +-- M3kFsrBackend    (new)
```

Do not perform a large refactor before the first FSR frame. Initially, the shared-input structure can be a thin adapter around the current globals.

## FSR-1 fixed proof-of-life

The first hardware candidate has exactly one goal: **an FSR reconstructed frame reaches GTA IV's presenter without altering the DLSS baseline**.

Initial settings:

- fixed Quality mode
- FSR context on the existing 64-bit Vulkan device
- sharpening/RCAS: OFF
- frame generation: OFF
- reactive mask: null
- transparency/composition mask: null
- auto exposure: ON
- explicit history reset
- debug checking: ON for test builds
- NR: irrelevant/off
- existing global LOD bias remains 0.0

No UI quality selector yet.

## Resource mapping

### Color

Use the true DXVK source exposed by `M3K_QueryPresentSourceV1`.

Expected initial format: `VK_FORMAT_B8G8R8A8_UNORM`.

The FSR input must be the real render-resolution color, not a downscaled copy of the final frame.

### Depth

Current guide is R32F.

The first backend must explicitly map the actual GTA/Lumenite depth convention to FSR flags and camera parameters. Do not copy NGX depth assumptions blindly.

### Motion vectors

Current guide is R16G16F and is estimated by Lumenite.

FSR expects current-to-previous motion vectors and receives an explicit `motionVectorScale`. The sign and scale are a hardware-validation item; do not hard-code the DLSS values as truth.

### Jitter

Pass the exact raster jitter used for the current frame, converted to FSR's convention.

Do not copy the current NGX compensation expression directly. Log raster jitter and FSR dispatch jitter side by side.

### Output

Allocate a dedicated FSR output image at presenter resolution with storage/UAV-compatible usage required by FidelityFX.

After FSR dispatch, copy/blit the completed FSR output into the same final presentation point currently used by reconstruction.

## Vulkan FidelityFX setup

Use SDK v1.1.4 APIs:

- `ffxGetScratchMemorySizeVK`
- `ffxGetDeviceVK`
- `ffxGetInterfaceVK`
- `ffxGetCommandListVK`
- `ffxGetResourceVK`
- `ffxFsr3UpscalerContextCreate`
- `ffxFsr3UpscalerContextDispatch`
- `ffxFsr3UpscalerContextDestroy`

Pin the SDK by tag **and commit SHA** in the experimental build.

## Lifecycle

The existing 1800 ms ReShade runtime-churn quarantine becomes a shared submission gate.

Rules:

1. Never dispatch FSR while the runtime-churn hold is active.
2. Do not destroy an FSR context/resources from an unsafe runtime-destroy callback while GPU work may still reference them.
3. Defer destruction until the Vulkan work is retired/safe.
4. Recreate/reset FSR when render/output dimensions or device identity change.
5. Set FSR `reset=true` on the first valid frame after recreation, resolution change, jitter-sequence reset, or camera/history discontinuity.

## Logging required before hardware test

Initialization:
- SDK/upscaler version
- Vulkan device identity
- render/output dimensions
- color/depth/MV formats
- context flags
- auto exposure / sharpening / masks

Dispatch (periodic):
- frame index
- render/output dimensions
- raster jitter
- FSR jitter
- MV scale
- reset
- delta time
- SDK result code

Lifecycle:
- context create/destroy/deferred destroy
- quarantine enter/exit
- resource recreation
- history reset reason

## FSR-1 success criteria

1. GTA IV reaches gameplay.
2. FSR context creates.
3. FSR dispatch succeeds repeatedly.
4. Displayed image is visibly FSR output.
5. No startup/menu-transition crash.
6. ReShade remains responsive.
7. Color/depth/MV inputs are valid.
8. Jitter is logged.
9. Candidate can be removed/restored cleanly.
10. Existing v1.1.0 DLSS path is byte-for-byte untouched by the candidate.

## Next implementation step

Build a dedicated experimental FidelityFX Vulkan module/library from SDK v1.1.4, then add a **single public stage** that injects the smallest FSR backend hook into the frozen M3K Vulkan adapter. Package it only through a manually-triggered experimental workflow; do not modify production release workflows.
