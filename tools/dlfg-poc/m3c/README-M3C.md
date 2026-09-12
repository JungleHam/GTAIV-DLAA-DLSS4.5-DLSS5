# M3C: toward continuous 2x DLSS-G

M3B-1 has passed: one genuine NVIDIA DLSS-G generated frame was validated, transferred from the Feeder's D3D12 NGX session into the shared Vulkan image, copied into an acquired swapchain image, and presented successfully before the original frame.

M3C deliberately proceeds in smaller steps. Do not call any M3C-0 result "continuous 2x".

## M3C-0: bounded safe-reuse stress test

M3C-0 reuses the already-proven M3B-1 producer/consumer path eight times. Its purpose is to prove that the feature-11 handle, validation readbacks, shared D3D12/Vulkan image, ownership transfer, swapchain insertion path, command buffer, and binary semaphores can all survive repeated generated-frame cycles.

It remains intentionally conservative:

- each generated frame still uses M3B-1's real A/B evaluation and CPU validation;
- OptiScaler waits `vkQueueWaitIdle` after the generated/original presentation pair before acknowledging the external image;
- only after that acknowledgement does the Feeder recycle its M3B-1 state for the next A/B pair;
- the test stops recycling after eight successfully consumed generated frames;
- no second NGX lifecycle is created;
- the M3B-1A ABI and D3D12->Vulkan producer timeline are unchanged.

The queue-idle stall is intentional. It makes reuse of the single external image and the existing binary semaphores unambiguous. A later M3C milestone must replace that stall with a proper resource ring and explicit completion signaling before any performance or cadence claim.

## Expected success evidence

Feeder should repeatedly log:

```text
M3C-0: consumer safely retired generated serial=...
M3C-0: safely recycled generated frame state; next sequential A/B pair may arm (.../8 consumed)
```

OptiScaler should repeatedly log:

```text
M3C-0: safe recycle after queue idle -> 0 for serial=...
M3C-0: generated frame N/8 presented and safely recycled; serial=...
```

The bounded milestone is reached only with:

```text
MILESTONE M3C-0 PASSED: 8 genuine DLSS-G frames generated, presented, and safely recycled through the single-image handoff
```

This proves repeated safe reuse, not correct 2x pacing.

## Local staging

Start from the M3B-1 hardware-pass source tree. The M3B-1 loading/MV retry helper must already have been applied to the ignored local Feeder checkout.

From repo root:

```powershell
git fetch origin
git switch gtaiv-vulkan-fg-continuous
git pull
powershell -ExecutionPolicy Bypass -File ".\tools\dlfg-poc\m3c\APPLY-M3C0-REPEAT.ps1"
```

Then rebuild both experimental binaries using the same build scripts used for M3B-1:

```powershell
.\tools\dlfg-poc\m2b\BUILD-M2B-PROBE.bat
.\tools\dlfg-poc\m3a-os\BUILD-M3A-OS.bat
```

Do not overwrite the `checkpoint/m3b1-one-shot-pass` branch. It is the rollback/reference checkpoint.

## What comes after M3C-0

M3C-1 should remove CPU validation from the live cadence path and pair generated output with the correct real-frame presentation rather than publishing it several frames later.

M3C-2 should replace the single-image + queue-idle handoff with a small reusable external-image ring and explicit Vulkan->D3D12 completion signaling.

Only after those are stable should the project attempt a sustained `real -> generated -> real` cadence and measure displayed FPS/latency.
