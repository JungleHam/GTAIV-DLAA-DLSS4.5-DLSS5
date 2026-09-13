# M3D — injected-present / real-present gate

M3C proved that native NVIDIA feature-11 output can be queued through a three-entry publication FIFO and consumed continuously, but the hardware run felt visibly jumpy. The log explained why: the Feeder's `vk_frame`/feature-11 path advanced about twice as often as GTA IV's actual `vkQueuePresentKHR` cadence. After the initial three queued frames, M3C settled into source-frame deltas of roughly two, while OptiScaler's consumer remained consecutive.

The M3D hypothesis is that OptiScaler's synthetic generated-frame `vkQueuePresentKHR` can re-enter the ReShade/Feeder layer chain (and some chains may call the technique more than once inside one genuine present). Temporal history must advance only once for each genuine game present.

M3D keeps all proven pieces:

- M3B-2B native NVIDIA feature-11 producer and temporal reset behavior;
- M3B-2A three shared images, external ownership transfers, producer timeline, and GPU-confirmed consumer-done return;
- M3C three-entry CPU publication FIFO;
- M3B-2A OptiScaler insertion order: generated frame, then original real frame.

It adds one default-off Feeder flag:

```ini
dlfg_m3d_injected_present_gate=0
```

For the M3D hardware test use `1` together with `dlfg_m3b2b_native=1` and `dlfg_m3c_queue=1`.

## Origin marker

The M3D OptiScaler binary exports `DLSS5_M3D_IsInjectedPresentActive`. It is backed by a thread-local depth counter and is true only around OptiScaler's synthetic generated-frame present (and the emergency acquired-image release present). The forwarded original GTA IV present is deliberately not marked.

The Feeder present hook resolves that export lazily. It maintains a genuine-present serial that advances only on an unmarked present and an injected-present counter for diagnostics.

At the top of `FeedFrameVk`, before `g.vk_frame` increments or any DLAA/DLSS-G work is recorded, M3D:

1. returns immediately if the current present is marked synthetic;
2. returns if this is a second Feeder callback under the same genuine-present serial;
3. accepts only the first callback under a new genuine-present serial.

Thus `sourceFrame + 1` under M3D means one new genuine GTA IV present, not merely one ReShade callback.

## Expected hardware result

A healthy M3D run should show:

- `M3D: accepted genuine real-present callback ...` steadily increasing;
- injected and/or duplicate callbacks being suppressed when the layer chain produces them;
- M3C publications advancing `sourceFrame` by 1 for long runs;
- `MILESTONE M3C PRODUCER PASSED` after 300 consecutive genuine-present publications;
- M3B-2B native producer and M3B-2A consumer milestones still passing;
- three-slot backpressure absent or limited to startup/transient events;
- visibly smoother pacing than the M3C hardware run.

The build remains isolated and writes nothing into GTA IV. Keep FusionFix **Windowed = On** and **Windowed Borderless = On** during the hardware test. Do not use Alt+Enter or switch Windowed Off; exclusive/fullscreen switching is a separately confirmed crash path in this stack.
