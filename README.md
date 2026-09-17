# GTA IV — DLAA + DLSS 4.5 + DLSS 5 Neural Rendering

A streamlined DLAA / DLSS stack for **GTA IV: Complete Edition**. Tested on **RTX 4070 Ti SUPER**.

## Install — 3 steps

### 1. Install FusionFix

Install [GTA IV FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) first, launch the game once, then close it.

### 2. Install DLAA + ReShade patch

Right-click **`install/Install-DLAA.bat` → Run as administrator**.

Enter the folder that contains `GTAIV.exe`, confirm, and let it finish. This installs the DLAA baseline **and** the ReShade input patch in one step.

Launch GTA IV once and press **Home**. ReShade should open and accept mouse/keyboard input.

### 3. Install DLSS Full + Neural Rendering

Right-click **`install/Install-DLSS-Full.bat` → Run as administrator**.

Enter the same GTA IV folder and confirm. The installer detects RTX 40/50 and chooses the matching Neural Rendering runtime automatically.

After install, open:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

That menu controls DLAA/DLSS mode, Neural Rendering, NR passes, diagnostics, and the full DLSS/DLAA processing toggle.

> **Important:** keep GTA IV's own resolution set to your display's native resolution. DLSS modes change the internal render resolution separately.

## Prerequisites

Install these before running Step 2 or Step 3:

| Requirement | Install / recommendation |
|---|---|
| **Git for Windows** | [Download](https://git-scm.com/download/win) — default options are fine. |
| **Python 3** | [Download](https://www.python.org/downloads/windows/) — enable **Add python.exe to PATH** during setup. |
| **Visual Studio 2022 Build Tools** | [Download](https://aka.ms/vs/17/release/vs_BuildTools.exe) — select **Desktop development with C++**, including x86/x64 MSVC tools and a Windows SDK. |
| **NVIDIA driver** | [Download](https://www.nvidia.com/en-us/drivers/) — use a current driver. Neural Rendering needs the newer DLSS 5-capable driver branch. |

The installers check these and stop before changing the game if something required is missing.

## Neural Rendering runtime

The final installer has two verified paths:

| GPU | Runtime |
|---|---|
| **RTX 50** | Original **NVIDIA-signed DLSS NR 310.8.0** runtime. |
| **RTX 40** | **RTX 40 compatibility 310.8.0** runtime used and tested by this project. |

RTX 40/50 selection is automatic when Windows reports the GPU normally. Other GPU generations are not part of the release-supported NR path yet.

Neural Rendering is installed **OFF by default**. DLSS quality defaults to **Quality** and NR passes default to **1**.

## What the project adds

- DLAA at native resolution.
- DLSS 4.5 Super Resolution: Custom Ultra Quality 77%, Quality, Balanced, Performance, Ultra Performance.
- DLSS 5 Neural Rendering with an in-game toggle.
- Automatic 1485×835 startup stabilization for stable temporal reconstruction.
- ReShade controls that work through the 32-bit GTA IV / 64-bit renderer bridge.
- Safe in-game master OFF/ON toggle for DLSS, DLAA, NR and temporal jitter.

## Troubleshooting

Main log:

```text
GTAIV\.trex\dlss5-feed.log
```

Useful docs:

- [DLSS Full details](docs/DLSS-FULL.md)
- [Verification / logs](docs/VERIFY.md)
- [ReShade input patch](docs/RESHade-INPUT-PATCH.md)

`DLSS-Full-Control.bat` is only for launch, startup repair, status and logs. Normal settings belong in ReShade.

## Uninstall / rollback

Run `Uninstall-DLSS-Full.bat` from the GTA IV folder to return to the preserved DLAA baseline.

The installers create backups before replacing the working stack.

## Credits

[FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) · [b-bridge](https://github.com/gutbash/b-bridge) · [DXVK](https://github.com/doitsujin/dxvk) · [ReShade](https://reshade.me/) · [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) · [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX)

Exact pinned versions and hashes are in [`manifests/versions.json`](manifests/versions.json).
