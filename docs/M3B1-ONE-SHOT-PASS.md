# M3B-1 one-shot native DLSS-G presentation checkpoint

Date: 2026-09-13
Branch: `gtaiv-vulkan-fg-present`

## Hardware result

M3B-1 passed on the RTX 4070 Ti SUPER test system.

The Feeder waited through GTA IV loading until the existing guide probes reported both valid non-flat depth and meaningful motion vectors, then reused the existing D3D12 NGX session to create NVIDIA feature 11 and evaluate one sequential real-frame pair.

Observed successful pair:

- guide probe frame 1200: mean MV `1.284968 px`, max `2.67 px`, `93%` non-zero
- depth probe frame 1200: min `0.388186`, max `0.404795`, variance `3.05e-05`
- `NGX_D3D12_CREATE_DLSSG -> Success`
- frame A `1203`: evaluate `reset=1 -> Success`
- frame B `1204`: evaluate `reset=0 -> Success`
- generated output checksum `a53194da74f34bf5`
- generated output non-zero pixels `3686400/3686400`
- generated differs from A: `2947980` pixels (`79.969%`)
- generated differs from B: `2941743` pixels (`79.800%`)
- generated published as serial `1`, readyValue `1204`

The OptiScaler Vulkan presenter then consumed that exact generated image:

- consumer acquired swapchain image `2` successfully
- `vkQueueSubmit2` submission result `0`
- generated-frame present result `0`
- original-frame present result `0`
- final log: `MILESTONE M3B-1 PASSED: genuine NVIDIA DLSS-G generated frame presented to GTA IV live Vulkan swapchain`

This is the first checkpoint where the project can legitimately claim that GTA IV displayed one genuine NVIDIA DLSS-G generated frame on-screen through the live Vulkan swapchain.

## Known-good binaries

Feeder SHA-256 after the loading/MV retry fix:

`2B42CD609FABB5A74765D6BC1EAEE10866A75041D82613CABA7E5DB3AC01C774`

Known-good OptiScaler M3B-1 build SHA-256:

`AFED313287550A3D78401140532EE0AE22AC73D9DA27391ADD6AE1BFE06810DB`

## Active test configuration

`dlss5-feed.cfg`:

```ini
dlfg_m2b_probe=0
dlfg_m2b_eval=0
dlfg_m2c_prearm_create=0
dlfg_m3b1a_publish=0
dlfg_m3b1_present=1
```

`OptiScaler.ini`:

```ini
[Debug]
GtaivVulkanPresentInstrumentation=true
GtaivVulkanOneShotExternalPresent=true
GtaivVulkanOneShotDuplicatePresent=false
```

Deep Fried Chicken was physically absent. OptiScaler DLSS-NR remained the neural consumer.

## Loading/MV retry fix

`tools/dlfg-poc/m2b/APPLY-M3B1-LOADING-RETRY.ps1` is part of this checkpoint. It changes only M3B-1 arming/retry behavior in the local Feeder checkout:

- valid depth alone is not sufficient to arm the one-shot test;
- the latest periodic MV probe must report mean motion greater than `0.05 px`;
- a zero-MV/material-motion A/B validation rejection becomes retryable instead of terminal.

No M3B-1A transport, external-frame ABI, Vulkan ownership barrier, timeline synchronization, OptiScaler consumer, or presentation logic is changed by that fix.

## Remaining limitation

This checkpoint is still one-shot only. It proves generation and presentation of a single DLSS-G interpolated frame. It does **not** prove continuous 2x frame generation, stable pacing, long-run resource reuse, or frame-latency behavior.

The next milestone is M3C: continuous `real -> generated -> real` presentation using the already-proven feature-11 producer and Vulkan handoff without introducing another NGX lifecycle.
