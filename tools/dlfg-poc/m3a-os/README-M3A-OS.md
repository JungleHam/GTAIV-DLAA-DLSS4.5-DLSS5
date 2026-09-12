# M3A-OS: OptiScaler Vulkan presentation instrumentation

This is the first GTA IV presentation-path experiment. It is **observation only**: it does not acquire a swapchain image, submit a command buffer, modify `VkPresentInfoKHR`, call `vkQueuePresentKHR`, create a DLSS-G feature, evaluate DLSS-G, or write an interpolated frame anywhere.

It preserves the established DLAA + DLSS5 Neural Rendering + off-screen DLSS-G baseline. The source is the pinned DLSSNR fork commit `973761621353b99bee3dc7d4bb27b117fef2644f` from `Dagherbou/OptiScaler_DLSSNR`.

## What is recorded

When enabled, the Vulkan hook logs each newly observed swapchain: device, physical device, HWND, extent, format, colour space, image usage, requested and actual image counts, present mode, sharing mode, supplied queue-family indices, and old swapchain. It resolves (without calling) `vkAcquireNextImageKHR`, `vkGetSwapchainImagesKHR`, `vkQueueSubmit`, and `vkQueueSubmit2`.

Presents receive a process-monotonic serial. The first 16, every 300th, non-standard multi-swapchain/wait cases, and errors log the queue, thread ID, known overlay queue family or `unknown`, swapchain, image index, wait semaphore count and handles, and the real return code.

The actual image count is queried with `vkGetSwapchainImagesKHR` only after a successful swapchain creation and only when the flag is on. No M3A-OS code calls acquire or either submit entry point.

## Build

Run `BUILD-M3A-OS.bat`. It clones/patches the source under the ignored `OptiScaler` folder, requires Visual Studio 2022 C++ x64 Build Tools, and writes only `m3a-build\OptiScaler-M3A-OS.dll`. It never accesses GTA IV or `.trex`.

## Hardware test

There is deliberately no automatic installer. With GTA IV and `NvRemixBridge.exe` closed, make a manual backup of the existing live OptiScaler binary and its `OptiScaler.ini`, then manually substitute only the experimental binary in the already-proven OptiScaler location. Do not replace Feeder, DXVK, ReShade, b-bridge, or any NVIDIA runtime. Restore the exact binary/config immediately after collecting the log.

In the live OptiScaler configuration, add this default-off diagnostic section:

```ini
[Debug]
GtaivVulkanPresentInstrumentation=true
GtaivVulkanOneShotDuplicatePresent=true
```

For an M3A-only inspection, leave `GtaivVulkanOneShotDuplicatePresent=false`. Enable file logging through the normal OptiScaler settings. Launch GTA IV, reach gameplay, then close it and inspect `OptiScaler.log`. Set both flags back to `false` before any ordinary play session.

M3A-OS is ready for hardware testing when the log contains `M3A-OS: swapchain created`, `M3A-OS: resolved Vulkan pointers`, and a series of `M3A-OS: present serial=` lines. This milestone does not pass until that one-run log demonstrates the final swapchain/image/semaphore/present contract needed to design a later, safe two-present sequence.

## M3B-0: one-shot duplicate-frame insertion

M3A-OS has passed on the GTA IV test path: the final queue is family 0, the `B8G8R8A8_UNORM` 2560x1440 swapchain has three images and `TRANSFER_SRC|TRANSFER_DST`, and normal presents have one wait semaphore. M3B-0 uses that measured contract to test exactly one copied-image two-present sequence. It is not DLSS-G and does not enable OptiFG.

`GtaivVulkanOneShotDuplicatePresent=false` is the default. With it set to `true`, M3B-0 waits for 300 successfully completed normal presents, checks the measured contract again, then attempts once per swapchain. It acquires one extra image with zero timeout, waits in one copy submit on both the game render-finished semaphore and its acquire semaphore, signals separate `duplicateReady` and `originalReady` semaphores, presents the duplicate first, and forwards the original game image second waiting on `originalReady`.

The game semaphore is consumed only by the copy submit; it is never waited twice. If no additional image is immediately available, M3B-0 logs the miss and leaves the game present unchanged. Resources remain allocated until swapchain recreation, when they are rebuilt for the new swapchain. M3B-0 passes only if the log records successful submit, duplicate present, original present, and `MILESTONE M3B-0 PASSED`.

## M3B-1A: one-shot external shared-image presentation

M3B-1A does not create or evaluate DLSS-G. With the default-off Feeder setting
`dlfg_m3b1a_publish=1`, Feeder creates one dedicated 2560x1440
`B8G8R8A8_UNORM` D3D12 image, imports it into the game's Vulkan device, copies
the completed post-NR output into it once, returns it to COMMON/GENERAL external
rest, and publishes it only after queuing `fence12_out` value `n`. The resource
is immutable after publication and remains alive until queue-idle teardown.

With `GtaivVulkanOneShotExternalPresent=true`, OptiScaler queries the versioned
Feeder ABI at the first real present after publication. Its single copy submit
waits on the game's binary semaphore, the extra-image acquire semaphore, and
Feeder's imported `vk_sem_out` timeline at `n`. The command buffer acquires the
published image from `VK_QUEUE_FAMILY_EXTERNAL`, copies it to the extra
swapchain image, restores GENERAL, releases it back to EXTERNAL, then signals
separate inserted-frame and original-frame binary semaphores. M3B-0 is
suppressed while this flag is enabled.

For the hardware test, manually stage both isolated binaries and add only:

```ini
# dlss5-feed.cfg
dlfg_m3b1a_publish=1

# OptiScaler.ini [Debug]
GtaivVulkanOneShotExternalPresent=true
GtaivVulkanOneShotDuplicatePresent=false
```

Success requires `M3B-1A producer copy complete`, `M3B-1A producer fence
signaled value=`, consumer acquire/submit/present results of zero, and finally
`MILESTONE M3B-1A PASSED`. This contract passed twice on the target hardware,
including after Feeder-resource and swapchain recreation.

## M3B-1: one-shot genuine NVIDIA DLSS-G presentation

M3B-1 preserves the proven M3B-1A ABI, timeline wait, external ownership
barriers, Vulkan copy, and dual-present sequence. Only the Feeder producer
changes: genuine NVIDIA feature 11 writes the interpolated image directly into
the dedicated shareable D3D12 resource. It reuses Feeder's existing D3D12 NGX
session and never performs another NGX Init or Shutdown.

`dlfg_m3b1_present=0` is the compiled Feeder default. When enabled, the one-shot
producer requires DFC to be absent, FrameGeneration Available=1, valid non-flat
depth, motion vectors, and two sequential real frames after startup. It records
reset=1 for frame A and reset=0 for frame B, returns the immutable output to
COMMON, queues the existing `fence12_out` signal, validates a CPU readback, and
only then publishes through the unchanged ABI. A zero sampled MV field is
accepted only when A and B are also static.

For the paired hardware test, manually stage both isolated binaries and use:

```ini
# dlss5-feed.cfg (DFC must be absent)
dlfg_m3b1a_publish=0
dlfg_m3b1_present=1

# OptiScaler.ini [Debug]
GtaivVulkanOneShotExternalPresent=true
GtaivVulkanOneShotDuplicatePresent=false
```

Do not enable the older M2B/M2C evaluator flags for this run. `MILESTONE M3B-1
PASSED: genuine NVIDIA DLSS-G generated frame presented to GTA IV live Vulkan
swapchain` is emitted only when feature 11 created, both evaluations succeeded,
the output passed validation, and both the inserted and original live presents
returned success. This remains strictly one-shot; continuous FG and pacing are
not implemented.
