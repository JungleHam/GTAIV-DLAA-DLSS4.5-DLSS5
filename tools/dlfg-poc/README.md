# DLFG milestone 1.2 POC

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

## Build

The GitHub Actions workflow builds milestone 1.2 automatically. Local build support uses the same pinned dependencies:

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
Can NVIDIA NGX create a Vulkan DLSS-G feature at 2560x1440 on this RTX 4070 Ti SUPER?
```

If it still returns `FAIL_InvalidParameter`, the next experiment is runtime-version alignment rather than more invasive game injection.

## What comes after feature creation works

Only after isolated feature creation succeeds:

- milestone 2: integrate on the **existing renderer/feeder device**, not a second NGX context, and produce one off-screen interpolated frame;
- milestone 3: add a safe 2x presenter/pacer (`real -> generated -> real`);
- milestone 4: place FG after the DFC Neural Rendering output and test `DLAA -> DLSS5 NR -> DLSS FG`.

The known-good main DLAA/DLSS5 installer remains untouched until these experiments are stable and reversible.
