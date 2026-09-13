# M3B-2B: continuous native NVIDIA DLSS-G over the proven reusable transport

M3B-2B is the next milestone after M3B-2A. It keeps the M3B-2A Vulkan presentation and consumer-return transport unchanged, but replaces the copied post-NR producer with genuine NVIDIA feature-11 (DLSS Frame Generation) output.

## Proven prerequisites

The hardware test already established both halves separately:

- **M3B-1:** genuine NVIDIA feature-11 output was generated, validated, and presented once to GTA IV's live Vulkan swapchain.
- **M3B-2A:** the three-slot reusable external-image transport ran for **2760 consecutive insertions** with GPU-confirmed consumer return and no observed backpressure or consumer-done failure during normal play.

The fullscreen/exclusive transition is a separate known crash path. Alt+Enter and FusionFix `Windowed = Off` can crash/freeze this Vulkan stack. That issue is **not** part of M3B-2B acceptance. Hardware testing for this milestone must remain in the already-working windowed-borderless mode.

## Architecture

M3B-2B deliberately reuses the components that have already passed:

1. GTA IV / ReShade supplies the current Vulkan colour, depth and motion-vector images.
2. Feeder's existing Vulkan -> D3D12 transport fills `SLOT_OUTPUT`, `SLOT_DEPTH` and `SLOT_MV`.
3. The normal DLAA/NR evaluation resolves the current real frame into `SLOT_OUTPUT`.
4. The existing M3B-1 code creates native NVIDIA feature 11 in the Feeder's already-running D3D12 NGX session and validates a one-shot A/B result first.
5. After that bootstrap reaches `kM2bPassed`, M3B-2B evaluates the same feature continuously.
6. Feature-11 output is written into the already-proven shareable M3B-1 output UAV (`g.m3b1a_tex12`).
7. A free slot from the proven M3B-2A three-image ring receives that generated frame.
8. The unchanged M3B-2A ABI publishes the ring slot to the unchanged OptiScaler consumer.
9. OptiScaler inserts that image into the live Vulkan present sequence and signals the shared consumer-done timeline after both generated and original presents.
10. Feeder may reuse a ring slot only after D3D12 observes that consumer-done value.

No second NGX initialization, device, queue, command list, feature-11 hook, OptiFG path or Deep Fried Chicken path is introduced.

## Temporal-history policy

The one-shot M3B-1 bootstrap includes asynchronous CPU validation, so there can be real game frames between its B frame and the frame on which `kM2bPassed` is observed. M3B-2B therefore does **not** assume that old feature history is temporally adjacent.

On entering continuous mode it performs one `reset=true` native feature-11 evaluation to seed fresh history and does **not** publish that reset output. The next valid moving frame uses `reset=false` and becomes the first continuous generated insertion.

The same policy is used after a real Feeder reset or after depth/motion validity is lost: pause publication, seed history with `reset=true`, then resume generated insertions on the following valid frame.

## Backpressure policy

Transport availability must never stall GTA's render thread.

If all three reusable slots are still in flight, or a prior publication has not yet been CPU-acknowledged, M3B-2B still evaluates feature 11 so its temporal history stays current, but it drops that generated presentation for the frame. Once a slot becomes free, generated publication resumes.

This preserves the M3B-2A rule that no D3D12 write may overlap Vulkan consumption of the same slot.

## Failure containment

All new behavior is default-off.

A normal failed NGX evaluate disables the M3B-2B native stream while leaving the ordinary real-frame path available. An SEH-protected NGX exception marks the current command list unsafe; the caller aborts that list using the same containment rule already proven by M2B/M3B-1.

Deep Fried Chicken must remain absent. M3B-2B intentionally refuses native streaming if DFC is present.

## Build

From the repository root:

```bat
tools\dlfg-poc\m3b2b\BUILD-M3B2B.bat
```

The wrapper first rebuilds the exact M3B-2A base, applies the M3B-2B Feeder patch, then rebuilds only the Feeder. The OptiScaler M3B-2A consumer binary is reused unchanged.

Outputs:

```text
tools\dlfg-poc\m3b2b\m3b2b-build\dlss5-feed-m3b2b.addon64
tools\dlfg-poc\m3b2b\m3b2b-build\OptiScaler-M3B2B.dll
```

The build wrapper never copies anything into GTA IV.

## Hardware-test configuration

Feeder (`dlss5-feed.cfg`):

```ini
dlfg_m2b_probe=0
dlfg_m2b_eval=0
dlfg_m2c_prearm_create=0
dlfg_m3b1a_publish=0
dlfg_m3b1_present=0
dlfg_m3b2a_stream=0
dlfg_m3b2b_native=1
```

OptiScaler keeps the already-proven M3B-2A consumer settings:

```ini
[Debug]
GtaivVulkanPresentInstrumentation=true
GtaivVulkanOneShotDuplicatePresent=false
GtaivVulkanOneShotExternalPresent=false
GtaivVulkanContinuousExternalPresent=true
```

FusionFix / display mode for this milestone:

```text
Windowed: On
Windowed Borderless: On
```

Do **not** press Alt+Enter and do **not** switch `Windowed` Off during this test.

## Expected producer logs

Bootstrap should still show the proven M3B-1 feature creation/evaluation/validation sequence. Then M3B-2B should log lines like:

```text
M3B-2B: M3B-1 bootstrap validated; seeding fresh continuous feature-11 history
M3B-2B: native feature-11 evaluate success reset=1 ...
M3B-2B: temporal history reset/seeded ... publication resumes next valid frame
M3B-2B: native feature-11 evaluate success reset=0 ...
M3B-2B: native generated frame copied to reusable slot=...
M3B-2B: published native serial=... slot=... sourceFrame=...
```

At 300 native publications:

```text
MILESTONE M3B-2B PRODUCER PASSED: 300 native NVIDIA feature-11 generated frames published through the reusable M3B-2A transport
```

## Expected consumer logs

The OptiScaler side remains M3B-2A and should continue reporting the same serials as reusable insertions:

```text
M3B-2A: inserted serial=... slot=... sourceFrame=... producerReady=... consumerDone=...
```

Its existing 300-consecutive transport milestone remains useful as the consumer-side synchronization proof.

## M3B-2B acceptance

A pass requires both sides in the same normal-play run:

- native feature-11 creation/bootstrap succeeds;
- continuous native `reset=false` evaluations continue;
- Feeder publishes at least 300 native generated frames;
- OptiScaler consumes/inserts corresponding M3B-2A serials continuously;
- consumer acknowledgements continue;
- no consumer-done submit failure;
- no repeated all-slots backpressure condition;
- no device loss or image corruption in ordinary windowed-borderless gameplay.

Fullscreen/exclusive switching is explicitly excluded from this milestone because it is already independently confirmed to crash the current GTA IV + FusionFix + Vulkan presentation stack.
