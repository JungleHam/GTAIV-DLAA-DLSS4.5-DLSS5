# M3B-2A — continuous reusable external-image transport (NO DLSS-G yet)

M3B-2A is the safety milestone immediately after the hardware-passed M3B-1 one-shot. It deliberately **does not evaluate NVIDIA feature 11**. Instead, it repeatedly copies Feeder's ordinary completed post-NR output through the same D3D12 -> Vulkan -> GTA IV swapchain route that continuous native DLSS-G will use in M3B-2B.

The known-good M3B-1 branch/commit remains untouched. This work lives on `gtaiv-m3b2a-continuous-transport`.

## What M3B-2A adds

### Feeder producer

- three dedicated shareable `B8G8R8A8_UNORM` D3D12 images imported into the existing Vulkan device;
- the existing `fence12_out` / `vk_sem_out` timeline remains the **producer-ready** contract;
- one new shared D3D12 fence imported as a Vulkan timeline semaphore becomes the **consumer-done** contract;
- a slot is reusable only after `consumerDoneFence12->GetCompletedValue()` reaches that slot's prior done value;
- before D3D12 writes a reused slot it also queues `ID3D12CommandQueue::Wait` on that consumer-done value, establishing the GPU-side Vulkan -> D3D12 dependency;
- if no slot is free, or the previous CPU publication has not been acknowledged, Feeder skips that insertion opportunity rather than stalling GTA IV;
- M3B-0, M3B-1A and M3B-1 remain separate/default-off paths.

### OptiScaler consumer

- one command buffer plus three distinct binary semaphores per ring slot;
- waits on the game render-finished semaphore, extra-image acquire semaphore, and Feeder's producer-ready timeline;
- acquires the shared source image from `VK_QUEUE_FAMILY_EXTERNAL`, copies it into an extra real swapchain image, restores `GENERAL`, then releases it back to EXTERNAL;
- presents the inserted image and then the original real GTA IV image using separate binary semaphores;
- submits a signal-only **post-present marker** on the same Vulkan queue after both presents;
- that marker signals Feeder's consumer-done timeline; only then is the publication CPU-acknowledged;
- any post-submit failure withholds consumer-done and makes that publication terminal rather than risking semaphore/image reuse.

The post-present marker intentionally protects both the external image and the per-slot binary semaphores from premature reuse.

## Default-off switches

Feeder adds the parse-only key:

```ini
dlfg_m3b2a_stream=0
```

OptiScaler adds under `[Debug]`:

```ini
GtaivVulkanContinuousExternalPresent=false
```

All new behavior is OFF unless both sides are explicitly enabled.

## Build

From the repository root:

```powershell
cd "B:\Stuff\Mods\bbridgepatchtest FG 1\GTAIV-DLAA-DLSS5-framegen-experimental"
git checkout gtaiv-m3b2a-continuous-transport
git pull
.\tools\dlfg-poc\m3b2a\BUILD-M3B2A.bat
```

The wrapper first lets the existing M2B/M3A build scripts prepare their pinned source trees, reapplies the known-good M3B-1 loading retry, applies the M3B-2A follow-up patches, rebuilds both modules, and copies **only build outputs** to:

```text
tools\dlfg-poc\m3b2a\m3b2a-build\dlss5-feed-m3b2a.addon64
tools\dlfg-poc\m3b2a\m3b2a-build\OptiScaler-M3B2A.dll
```

It prints SHA-256 hashes. It never writes to GTA IV or `.trex`.

## Hardware-test configuration

Manually stage the two M3B-2A binaries only after GTA IV and `NvRemixBridge.exe` are closed.

`dlss5-feed.cfg`:

```ini
dlfg_m2b_probe=0
dlfg_m2b_eval=0
dlfg_m2c_prearm_create=0
dlfg_m3b1a_publish=0
dlfg_m3b1_present=0
dlfg_m3b2a_stream=1
```

`OptiScaler.ini` under `[Debug]`:

```ini
GtaivVulkanPresentInstrumentation=true
GtaivVulkanOneShotDuplicatePresent=false
GtaivVulkanOneShotExternalPresent=false
GtaivVulkanContinuousExternalPresent=true
```

Keep DFC absent and OptiFG out of this project path.

## Expected markers

Feeder should first show:

```text
[feed] M3B-2A: created 3 reusable external-image slots + consumer-done timeline=
[feed] M3B-2A: slot 0 initialized GENERAL and released to D3D12
[feed] M3B-2A: published serial=... slot=... sourceFrame=... producerReady=... consumerDone=...
[feed] M3B-2A consumer acknowledged serial=...
```

OptiScaler should show:

```text
M3B-2A: captured swapchain
M3B-2A: resolved Feeder reusable-transport ABI
M3B-2A: created 3 per-slot command/semaphore sets
M3B-2A: inserted serial=... slot=... total=... consecutive=...
```

The first pass criterion is:

```text
MILESTONE M3B-2A PASSED: 300 consecutive reusable external-image insertions completed with GPU-confirmed consumer return
```

After that marker, keep playing for a few minutes and cause at least one swapchain/resource recreation if practical. The run is not considered reusable-transport-stable if there is a Vulkan/D3D12 device loss, a stuck publication, repeated consumer-done failure, binary-semaphore validation error, or corruption after recreation.

## What comes next

Only after M3B-2A passes on hardware do we implement M3B-2B. M3B-2B keeps this exact ring/ownership/completion/presentation machinery and replaces the producer copy with native NVIDIA feature-11 output, targeting:

```text
real A
-> generated A/B
-> real B
-> generated B/C
-> real C
```

No full-frame CPU readback/checksum is planned for the continuous path.
