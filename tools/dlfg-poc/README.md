# DLFG milestone 1 POC

This folder is an **isolated experiment** for adding NVIDIA DLSS Frame Generation to the existing GTA IV b-bridge/DLAA stack.

It does **not** modify the working renderer or present generated frames yet.

## Milestone 1 goal

Prove all of the following inside `NvRemixBridge.exe` on the target RTX GPU:

1. the x64 ReShade add-on loads;
2. NVIDIA's Vulkan NGX client initializes;
3. NGX reports DLSS Frame Generation available;
4. a private Vulkan graphics device can create an NGX DLSS-G feature at 2560x1440;
5. the feature is released cleanly without touching the game's swapchain.

Success is this line in `.trex\dlfg-probe.log`:

```text
SUCCESS: NVIDIA NGX DLSS Frame Generation feature was created on the RTX GPU.
```

This is deliberately a capability/feature-create probe only. It does **not** evaluate an interpolated frame yet.

## Safety model

The probe creates a second, private Vulkan instance/device on the NVIDIA GPU. It does not replace `d3d9vk_x64.dll`, does not patch the game's Vulkan swapchain and does not call `vkQueuePresentKHR`.

`UNINSTALL.bat` removes only the POC files and restores a pre-existing `nvngx_dlssg.dll` if one was present.

## Build

Double-click:

```text
BUILD.bat
```

It fetches pinned source/header dependencies only:

- ReShade 6.8.0 commit `18deaa52de0c425a78b329e9cb3c497281cd00ec`
- NVIDIA DLSS SDK 310.9.1 commit `374959484e79a640feaba44c93ac8cfb0a03f5b5`
- Vulkan-Headers commit `ee2ec5fd83dafce291024683b50dc89219333076`

Requirements are the same Visual Studio C++ build tools already used for the ReShade input patch.

Output:

```text
dlfg-probe.addon64
```

## Get the DLSS-G runtime

Double-click:

```text
GET-RUNTIME.bat
```

For this first experiment it downloads NVIDIA's official RTX Remix 1.5.2 release archive, verifies the published archive SHA256, extracts `nvngx_dlssg.dll`, then deletes the temporary archive. It does **not** install RTX Remix itself.

The download is large (~230 MB) because NVIDIA distributes the runtime inside the full Remix release package.

## Install / run

1. Fully close GTA IV.
2. Double-click `INSTALL.bat`.
3. Paste or drag the folder containing `GTAIV.exe`.
4. For the first test, keep the known-good DLAA path. Turning DFC neural processing off is preferred simply to reduce variables; it is not permanently changed by the installer.
5. Launch GTA IV and leave it running in a rendered scene for at least 5 seconds.
6. Close the game.
7. Open/send:

```text
GTAIV\.trex\dlfg-probe.log
```

## Expected progression

A healthy log should progress roughly through:

```text
runtime: nvngx_dlssg.dll found next to the add-on
NVSDK_NGX_VULKAN_RequiredExtensions -> ...
selected GPU: NVIDIA GeForce RTX ...
NVSDK_NGX_VULKAN_Init(...) -> 0x00000001
FrameGeneration.Available: ... value=1
DLSSG.MultiFrameCountMax: ...
NGX_VK_CREATE_DLSSG(...) -> 0x00000001 feature=...
SUCCESS: NVIDIA NGX DLSS Frame Generation feature was created on the RTX GPU.
MILESTONE 1 PASSED.
```

If it fails, send the complete `dlfg-probe.log`; each stage is intentionally logged so the next iteration has a precise failure point.

## Remove

Fully close GTA IV and double-click:

```text
UNINSTALL.bat
```

## What comes next

Only after this milestone succeeds:

- milestone 2: feed resolved color + Lumenite motion vectors + depth to DLSS-G and produce an **off-screen** interpolated image;
- milestone 3: add a safe 2x presenter/pacer (`real -> generated -> real`);
- milestone 4: move FG after the DFC Neural Rendering output and test `DLAA -> DLSS5 NR -> DLSS FG`.

Do not merge this experiment into the main installer until 2x presentation is stable and rollback has been tested repeatedly.
