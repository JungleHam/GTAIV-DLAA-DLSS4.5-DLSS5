# M3C - native DLSS-G throughput / pacing

M3B-2B hardware proof succeeded: native NVIDIA feature 11 generated frames were copied into the reusable three-slot transport, inserted into GTA IV's Vulkan swapchain, and GPU-returned safely.

The remaining throughput bottleneck was CPU publication serialization. The ring physically has three reusable GPU slots, but the exported ABI exposed only one `ready` publication at a time. The Feeder therefore evaluated feature 11 every real frame but could publish only after OptiScaler consumed the prior singleton publication. Hardware logs showed the characteristic source-frame sequence `1808, 1811, 1814, ...`.

M3C keeps the proven GPU resources and synchronization unchanged and replaces only the CPU publication state with a three-entry FIFO when `dlfg_m3c_queue=1` and `dlfg_m3b2b_native=1`.

## Safety invariants

- M3C is default OFF.
- M3B-2B remains unchanged on its hardware-passed checkpoint branch.
- The exported `DLSS5_QueryM3B2AExternalFrame` / `DLSS5_ConsumeM3B2AExternalFrame` ABI is unchanged.
- FIFO capacity equals the existing three GPU transport slots.
- A slot is still reused only after Vulkan's GPU-confirmed `consumerDoneValue` is visible to D3D12.
- Feature 11 continues evaluating when the FIFO/ring cannot accept another publication so temporal history remains current.
- No build script writes to GTA IV or `.trex`.
- Fullscreen/exclusive transitions remain outside this milestone. Test only FusionFix Windowed ON + Windowed Borderless ON.

## Hardware target

The producer milestone is:

`MILESTONE M3C PRODUCER PASSED: 300 consecutive native publications with sourceFrame delta=1 through the three-entry FIFO`

The existing OptiScaler consumer must simultaneously stay consecutive with no copy-submit, present, consumer-done, device-loss, or consume-ack failures.
