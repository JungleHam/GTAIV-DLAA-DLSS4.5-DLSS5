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

Public UI contract:

```text
Scaling Technology
[ Off ▼ ]
[ NVIDIA — DLAA / DLSS 4.5 ]
[ AMD — FSR ]
```

This is an explicit user choice, not GPU autodetection. NVIDIA hardware may run FSR and AMD hardware may select FSR without any NVIDIA reconstruction dependency. Selecting a backend changes which backend-specific controls are shown:

- NVIDIA: DLAA/DLSS presets, NVIDIA custom render scale, NVIDIA sharpening, NVIDIA-specific NR controls.
- AMD/FSR: FSR presets/custom render scale, FSR sharpening/RCAS, FSR-specific temporal diagnostics.
- Off: hide both reconstruction control groups and return to raw/native passthrough.

Each backend keeps its last-used settings independently so switching NVIDIA -> AMD -> NVIDIA restores the NVIDIA settings instead of copying AMD values across.

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

## Hardware checkpoint: FSR-P1 passed (2026-09-22)

RTX 4070 Ti SUPER / 2560x1440 hardware log proved:

- FSR 3.1.4 Vulkan context created successfully.
- Direct FSR Vulkan dispatch began at 1485x835 -> 2560x1440.
- More than 33,000 FSR frames were dispatched in one run.
- No FSR debug error, dispatch failure, crash, or NGX fallback occurred after initialization.
- NGX evaluate time remained 0.00 ms on the direct FSR path.
- Clean shutdown reached Vulkan-hook removal.

P1 also exposed a design bug rather than an FSR failure: the run remained pinned to the existing 1485x835 DLSS startup-prime size for the whole session. Because FSR bypassed the DLSS evaluation observer that completes startup prime, the prime never released to the intended quality size.

Therefore P2 must:

1. bypass DLSS startup-prime whenever FSR is selected;
2. give FSR its own render-size plan;
3. disable DLSS SR feature creation (SRProof=0) during the FSR test;
4. keep no-cross-backend-fallback behavior;
5. use the FidelityFX jitter phase-count helper for the FSR render/output ratio.

P2 still reuses the Feeder's existing shared Vulkan resource allocation/bootstrap. Full AMD independence requires removing that remaining NGX/D3D12 bootstrap in a later step.

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


## P5C hardware calibration — PASSED

P5C moved projection telemetry to the x64 bridge server so the hardware-proven
production `d3d9.dll` client remained untouched. The server read only the live D3D9
viewport plus GTA IV world-shader constants c0-c15 immediately before sampled draws.

Hardware results:
- 425 valid perspective samples accepted.
- 424/425 samples used the full 1708x960 gameplay viewport.
- Vertical FOV was overwhelmingly 45.0 degrees.
- Near plane clustered at 0.050000.
- 422/424 full-size samples clustered at approximately 1500 far plane.
- Two isolated full-size samples used approximately 24.7k far plane and are treated
  as secondary/alternate projections rather than the main gameplay camera.
- Depth projection was consistently normal (non-reversed candidate).
- The main FSR depth contract remains finite, not infinite.
- P4A exact raster jitter remained hardware-correct during the same run.

Default FSR camera contract after P5C:
- `cameraNear = 0.05`
- `cameraFar = 1500.0`
- `cameraFovAngleVertical = 45 degrees`
- depth inverted = false
- depth infinite = false

INI overrides remain supported for diagnostics and unusual camera/projection cases.


## P8 hardware validation — PASSED

P8 validated the explicit scaling selector together with independent AMD RCAS on hardware.

Observed:
- launch backend captured as AMD - FSR
- native Vulkan FSR session opened with no D3D12/NGX initialization
- calibrated camera contract remained near=0.05, far=1500, vertical FOV=45 degrees
- independent AMD RCAS started at 0.25 and accepted live UI changes through the full 0..1 range
- FSR direct Vulkan reconstruction remained active during RCAS changes
- live FSR scale changes succeeded at 33%, 100%, 77%, and 50%
- exact raster-jitter handoff returned active after resize/runtime churn and matched FSR jitter exactly
- temporary raw-nearest fallback occurred only while a requested render-size transition had not yet produced the new DXVK source
- final session shut down the FidelityFX context after Vulkan queue idle and exited cleanly

P8 is therefore the hardware baseline for the public AMD path.

Next lifecycle target:
- live Off <-> NVIDIA <-> AMD switching without process restart
- must reuse queue-idle / runtime-churn quarantine
- must never silently fall back across vendors
- requested and active backend remain separate until a transition commits successfully


## P9A.1 hardware validation — PASSED

P9A.1 validated live AMD FSR <-> Off switching while retaining the native Vulkan session.

Observed:
- AMD -> Off returned GTA to true native 2560x1440 before commit.
- Master-OFF completed its 30-frame native stability gate and 400 ms jitter drain.
- AMD -> Off then committed to raw/native passthrough and stopped FSR dispatch while retaining the native Vulkan session.
- Off -> AMD resumed FSR in the existing native Vulkan session without restart.
- The saved AMD render scale was restored correctly across Off.
- A second full AMD -> Off -> AMD cycle also passed.
- Live FSR scale changes at 66.7%, 77%, and 100% were confirmed, including the 1971x1109 source for 77%.
- Exact raster jitter resumed after AMD re-enable and matched FSR jitter.
- FidelityFX shut down only after Vulkan queue idle and the session exited cleanly.

P9A.1 is the frozen hardware baseline for AMD/native lifecycle work.

Next lifecycle target:
- P9B: isolate and prove live Off <-> NVIDIA session creation/teardown.
- Start P9B from sessionless Off.
- Keep AMD live crossing disabled/restart-gated in P9B so the new NVIDIA boundary can be tested independently.
- NVIDIA -> Off must use the proven DLAA Native drain, 30 stable frames, 400 ms jitter drain, then queue-idle session teardown.
- Off -> NVIDIA must not report the transition committed until the replacement D3D12/NGX session actually opens successfully.
- A failed NVIDIA open must roll back explicitly to Off/raw; never silently fall back to AMD.


## P9B.3 hardware validation — PASSED

P9B.3 validated the live sessionless Off <-> NVIDIA lifecycle after fixing the
NVIDIA reconstruction-finalizer race found by P9B.2 hardware testing.

Observed:
- startup Off reached true native 2560x1440 raw passthrough without opening D3D12/NGX/FSR
- Off -> NVIDIA succeeded three times
- each NVIDIA enable created real DLSS Quality reconstruction at 1707x960 -> 2560x1440 before the transition finalized
- NVIDIA -> Off was requested three times
- each request hit the explicit target guard: the NVIDIA reconstruction finalizer was blocked while the pending target was Off
- each Off request then completed the 30-frame native stability gate, jitter-off drain, queue-idle teardown, and committed sessionless Off on the first selection
- the former erroneous NVIDIA -> NVIDIA finalization did not recur
- final shutdown was clean

P9B.3 is the frozen hardware baseline for the NVIDIA/native lifecycle boundary.

Next lifecycle target:
- P9C: compose the independently proven AMD <-> Off and NVIDIA <-> Off boundaries
- direct NVIDIA <-> AMD user requests must serialize through an explicit Off/raw midpoint
- preserve P9A.1's retained native Vulkan session when AMD -> Off is the only requested boundary
- when leaving retained-Off for NVIDIA, retire the retained FSR session at queue idle before NGX opens
- sessionless Off -> AMD must open a native Vulkan FSR session and must not finalize until a real FSR dispatch succeeds
- no cross-vendor silent fallback; a target-open failure contains to Off/raw
