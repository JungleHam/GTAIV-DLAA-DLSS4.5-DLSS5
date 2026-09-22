# GTA IV FSR backend architecture

Status: **FSR-0 / implementation plan**  
Branch: `feature/fsr-3-1-5`  
Protected baseline: `main @ ed72c4ab301ed92763732577efa7eeaa8d3a3283`

## Locked product/test rules

These are hard requirements for all work after P1.

### Test packaging

Every test that changes files or settings must ship with two obvious BAT entry points:

1. **APPLY** — refuses to overwrite an existing unrestored test state, backs up every file/settings file it will change, then applies the test.
2. **RESTORE** — restores the exact saved files/settings and preserves the test log separately before restoring any previous log.

Do not ask the tester to paste PowerShell, edit INI keys manually, rename DLLs manually, or remember the old state.

### Reconstruction backend selector

The public selector is a single three-state backend choice:

```text
Off
DLAA / DLSS 4.5
FSR
```

There is no automatic cross-backend fallback.

- **Off**: raw/native passthrough.
- **DLAA / DLSS 4.5**: the existing protected NVIDIA path.
- **FSR**: an independent FidelityFX path.
- If the selected backend cannot initialize or dispatch, report that failure explicitly and remain on that backend's diagnostic/passthrough failure path. Never silently run another reconstruction backend.

### Backend isolation

DLAA/DLSS and FSR own separate configuration/state.

DLAA / DLSS owns:
- NVIDIA reconstruction profile/custom scale
- NVIDIA/DLSS sharpening value
- NGX feature/context state
- NVIDIA-specific capability queries and preset contracts

FSR owns:
- FSR render scale/quality choice
- FSR sharpening/RCAS value
- FidelityFX context/resources
- FSR-specific depth/MV/jitter conversion and masks

A Radeon FSR path must not require successful NGX initialization, an NGX feature, NVIDIA capability parameters, NVIDIA DLLs, or an NVIDIA GPU. Shared code is limited to backend-neutral GTA/DXVK inputs, resolution signaling, jitter/history metadata, lifecycle safety, and presentation.

P1 is allowed to borrow the already-proven NVIDIA-hosted render-size plumbing only as a temporary hardware proof. That dependency must be removed before the FSR backend is called AMD-ready or exposed in the final three-state selector.

### Neural Rendering

Treat Neural Rendering as a higher-level optional stage, not as proof that FSR and DLSS share a backend.

- NVIDIA hardware may use the current NVIDIA DLSS Neural Rendering path.
- AMD support, if used, must be a separately detected/tested AMD-compatible runtime/backend.
- Do not make FSR depend on NVIDIA's `nvngx_dlssnr.dll`.
- Do not silently install or load an unofficial AMD compatibility runtime. It must be explicit and independently testable.

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

The first hardware candidate has exactly one goal: **an FSR reconstructed frame reaches GTA IV's presenter without altering the DLSS baseline or silently falling back to NGX**.

Initial settings:

- fixed Quality mode for P1
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
11. With FSR selected, a failed FSR dispatch never evaluates DLSS/NGX for that frame.

## Next implementation step

Build a dedicated experimental FidelityFX Vulkan module/library from SDK v1.1.4, then add a **single public stage** that injects the smallest FSR backend hook into the frozen M3K Vulkan adapter. Package it only through a manually-triggered experimental workflow; do not modify production release workflows.
