# DLFG experimental POC

This folder is an **isolated experiment** for adding NVIDIA DLSS Frame Generation to the existing GTA IV b-bridge/DLAA stack.

## Important: milestone 1.1 in-game probe is retired

The first probe loaded a ReShade add-on into `NvRemixBridge.exe`, created a second Vulkan/NGX device in the same process, then shut that NGX context down. Live testing showed that this can destabilize the real DLAA/DLSS5 session during the legal-screen to game swapchain transition.

**Do not use `INSTALL.bat` for milestone 1.1.** It now refuses to install.

If you already installed the old probe, fully close GTA IV and run:

```text
UNINSTALL.bat
```

This removes only the experimental probe files and restores a pre-existing `nvngx_dlssg.dll` if one was present.

## What the logs proved before the crash

On the RTX 4070 Ti SUPER test system:

- HAGS is enabled;
- `NVSDK_NGX_VULKAN_GetFeatureRequirements(FrameGeneration)` reports supported;
- minimum hardware architecture is `0x190` (Ada);
- `FrameGeneration.Available = 1`;
- `FrameGeneration.NeedsUpdatedDriver = 0`;
- `DLSSG.MultiFrameCountMax = 1` (normal 2x frame generation);
- feature creation still returns `0xBAD00005` / `FAIL_InvalidParameter` for BGRA8, RGBA8 and RGBA16F.

The in-process probe also revealed an important version clue: NGX reports the Frame Generation feature as **310.2.1**, while the DLSS runtime in the working feeder path is **310.9.1**. That runtime/API mismatch is now one of the main suspects for the invalid-parameter result.

## Milestone 1.2: safe standalone probe

Milestone 1.2 runs in a **separate process**. Nothing is copied into GTA IV and the game must be closed while it runs.

The standalone executable is intentionally named `NvRemixBridge.exe` inside this experiment's `standalone` folder so NVIDIA's driver/NGX application matching is as close as practical to the real Remix bridge without touching the actual game process.

### Get the DLSS-G runtime

Run once:

```text
GET-RUNTIME.bat
```

It downloads NVIDIA's official RTX Remix 1.5.2 archive, verifies it, and extracts only `nvngx_dlssg.dll`.

### Run the safe probe

1. Fully close GTA IV.
2. Put the compiled `standalone\NvRemixBridge.exe` in this folder's `standalone` subfolder.
3. Double-click:

```text
RUN-STANDALONE.bat
```

The runner copies `nvngx_dlssg.dll` into the isolated folder, launches the probe, and prints the resulting log.

Send:

```text
standalone\dlfg-standalone.log
```

No Administrator prompt and no game-path input are required.

### Milestone 1.2: PASSED on RTX 4070 Ti SUPER

The isolated Vulkan probe confirmed:

- `FrameGeneration.Available = 1`
- `NeedsUpdatedDriver = 0`
- `MultiFrameCountMax = 1`
- `NGX_VK_CREATE_DLSSG = Success`

### Milestone 2A: PASSED on RTX 4070 Ti SUPER

The standalone evaluator performed two successful DLSS-G evaluations using fully synthetic Vulkan resources. Its bright-object horizontal centroids were `899.50` for Frame A, `938.25` for the generated frame, and `979.50` for Frame B (mathematical midpoint `939.50`). This proves actual off-screen interpolation, not merely feature creation.

This does **not** mean GTA IV frame generation works. M2B passed its off-screen real-resource evaluation with DFC physically absent: DLSS-G create and both evaluations succeeded, and CPU readback differed from both surrounding real frames. With DFC present and ARMED, a conventional post-arm feature-11 Create returned `PlatformError`; M2C-A is the default-off pre-arm coexistence root-cause test. It remains off-screen and does not present or modify the GTA IV backbuffer. See [m2b/README-M2B-PREP.md](m2b/README-M2B-PREP.md).

### Milestone 3A-OS: OptiScaler Vulkan presentation instrumentation

M3A-OS is a default-off **observation-only** experiment in the final OptiScaler Vulkan path. It records the real swapchain and throttled present contract, including image indices, wait semaphores, and return codes, while resolving (but never calling) the acquire/submit functions needed by a later design. It neither adds a present nor changes any `VkPresentInfoKHR` field, swapchain behavior, OptiFG setting, Streamline behavior, DLAA, DLSS5 NR, or Feeder NGX operation. See [m3a-os/README-M3A-OS.md](m3a-os/README-M3A-OS.md). It has passed hardware inspection and is not itself a presentation implementation.

M3A-OS and M3B-0 have passed on hardware, including M3B-0 after swapchain recreation. M3B-1A also passed twice: Feeder's one-shot shareable D3D12 image was synchronized, acquired from external ownership, copied into an extra Vulkan swapchain image, and presented before the original frame. M3B-1 now replaces only that producer image with genuine native NVIDIA feature-11 output; it remains default-off, one-shot, and has no continuous pacing loop.

## Build

The GitHub Actions workflow builds the standalone M2A evaluator. Local build support uses the same pinned dependencies:

- NVIDIA DLSS SDK 310.9.1 commit `374959484e79a640feaba44c93ac8cfb0a03f5b5`
- Vulkan-Headers commit `ee2ec5fd83dafce291024683b50dc89219333076`

CI build entry point:

```text
BUILD-STANDALONE-CI.bat
```

Output:

```text
standalone\NvRemixBridge.exe
```

## Goal

The standalone probe asks the same core question without risking the working game stack:

```text
Can NVIDIA NGX evaluate and produce a real Vulkan DLSS-G intermediate frame at 2560x1440 on this RTX 4070 Ti SUPER?
```

That question is now answered yes in the isolated process.

## What comes after feature creation works

After isolated interpolation succeeds:

- milestone 2B-PREP: passed real-resource acquisition and confirmation of the existing Feeder D3D12 NGX session;
- milestone 2B: passed one off-screen evaluation in that same session with DFC absent; no presentation;
- milestone 2C-A: default-off DFC/DLSS-G pre-arm coexistence root-cause test; no presentation;
- milestone 3A-OS: default-off final Vulkan swapchain/present instrumentation; no presentation;
- milestone 3B-0: passed default-off one-shot copied-frame duplicate/original presentation test;
- milestone 3B-1A: passed one-shot D3D12-to-Vulkan external-image presentation proof;
- milestone 3B-1: default-off one-shot genuine NVIDIA DLSS-G generated-frame presentation test;
- milestone 3 continuous: only after M3B-1 evidence, design a safe 2x DLSS-G presenter/pacer (`real -> generated -> real`);
- milestone 4: place FG after the DFC Neural Rendering output and test `DLAA -> DLSS5 NR -> DLSS FG`.

The known-good main DLAA/DLSS5 installer remains untouched until these experiments are stable and reversible.
