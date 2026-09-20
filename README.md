# GTA IV — DLAA + DLSS 4.5 + DLSS 5 Neural Rendering

## [Screenshots](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/tree/main/screenshots)

## Installation

> **You do not need to memorize this. The installer explains the same steps on screen.**

1. Download **`GTAIV-DLSS-Setup.exe`** from this project's [Releases](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases).
2. Run it as **Administrator**.
3. Select the GTA IV folder containing **`GTAIV.exe`**.
4. Choose **DLAA** or **Full DLSS**.
5. If FusionFix is missing, setup downloads and installs it automatically. Launch GTA IV once to the main menu, close it, then run setup again.
6. For a fresh DLAA foundation, setup asks for **ReShade 6.8.0 Full Add-On Support**. Start at [crosire/reshade](https://github.com/crosire/reshade), open the official website from the GitHub **About** box, download the 6.8.0 **Full Add-On Support** installer, and select that EXE. Do not run it yourself.
7. For **Full DLSS**, setup detects RTX 40/50 and downloads the matching Neural Rendering runtime automatically.
   - Already have the correct `nvngx_dlssnr.dll`? Check **I brought my own** and select it instead.
8. Finish setup and launch GTA IV.

Full DLSS starts with:

```text
DLSS profile: Quality
Neural Rendering: OFF
```

Open the in-game controls with:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

## Prerequisites

- **GTA IV: Complete Edition**
- **Windows 10/11 64-bit**
- **Administrator access** for the ReShade Vulkan layer
- An **NVIDIA RTX GPU** for DLAA / DLSS
- **RTX 40 or RTX 50** for this project's DLSS 5 Neural Rendering path
- The tested NR setup expects a recent NVIDIA driver; **615.00+** is recommended for the validated configuration
- **ReShade 6.8.0 Full Add-On Support** is the only normal manual download

The installer automatically obtains and verifies the GitHub-hosted parts it needs, including FusionFix, LumeniteFX, the GPU-matched NR package, and this project's runtime.

More exact hashes and pinned versions are in [`manifests/versions.json`](manifests/versions.json).

## What this solution is

GTA IV is a **32-bit Direct3D 9 game**, while modern DLSS and ReShade tooling is much happier in a 64-bit renderer.

This project bridges the two:

```text
GTAIV.exe (32-bit D3D9)
        |
        v
FusionFix
        |
        v
b-bridge client
        |
        v
NvRemixBridge.exe (64-bit)
        |
        v
Vulkan / custom DXVK presenter
        |
        v
ReShade + LumeniteFX
        |
        +--> DLAA
        |
        +--> DLSS 4.5 Super Resolution
        |
        +--> optional DLSS 5 Neural Rendering
        |
        v
display
```

### DLAA

DLAA runs the DLSS reconstruction path at native output resolution, mainly improving anti-aliasing and temporal stability without lowering the game's render resolution.

### DLSS 4.5 Super Resolution

For DLSS modes, GTA IV renders internally below the final output resolution. The project keeps the game's temporal jitter, depth/motion data, internal render size and DLSS input synchronized so reconstruction stays stable.

A short automatic startup stabilization phase is used before switching to the saved DLSS quality mode.

### DLSS 5 Neural Rendering

Neural Rendering is installed by **Full DLSS** but starts **OFF**. On RTX 40 the installer uses the tested compatibility runtime; on RTX 50 it uses the original NVIDIA-signed runtime.

If you already have the exact tested `nvngx_dlssnr.dll`, the installer can use your local copy through **I brought my own**. It is still hash-checked before use.

### ReShade input patch

GTA IV owns the game window, but ReShade runs inside the separate 64-bit bridge process. The project includes a small ReShade 6.8.0 patch that relays keyboard and mouse input across that process boundary so the ReShade overlay remains usable.

## Useful docs

- [Prerequisites and pinned packages](docs/PREREQUISITES.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Third-party components / redistribution policy](docs/THIRD-PARTY.md)
- [ReShade input patch](docs/RESHade-INPUT-PATCH.md)

## Credits

- [FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix)
- [b-bridge](https://github.com/gutbash/b-bridge)
- [DXVK](https://github.com/doitsujin/dxvk)
- [ReShade](https://github.com/crosire/reshade)
- [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder)
- [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX)
- [NVIDIA DLSS](https://github.com/NVIDIA/DLSS)
- [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo)

This is an independent community integration project and is not affiliated with Rockstar Games, NVIDIA, or the upstream projects above.
