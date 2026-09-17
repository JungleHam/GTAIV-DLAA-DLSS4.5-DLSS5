# GTA IV — DLAA + DLSS 4.5 + DLSS 5 Neural Rendering

A streamlined DLAA / DLSS stack for **GTA IV: Complete Edition**. Tested on **RTX 4070 Ti SUPER**.

## Install — 3 steps

### 1. Install FusionFix

Install [GTA IV FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix), launch GTA IV once, then close it.

### 2. Install DLAA + ReShade patch

Right-click **`install/Install-DLAA.bat` → Run as administrator**.

Enter the folder containing `GTAIV.exe` and confirm. The installer automatically installs:

- DLAA baseline
- official ReShade 6.8.0 Add-On Support
- the verified prebuilt ReShade input patch

Launch GTA IV once and press **Home**. ReShade should open and accept mouse/keyboard input.

### 3. Install DLSS Full + Neural Rendering

Right-click **`install/Install-DLSS-Full.bat` → ##Run as administrator**.

Enter the same GTA IV folder and confirm. The installer downloads the verified prebuilt runtime and selects the correct Neural Rendering file:

| GPU | Neural Rendering runtime |
|---|---|
| **RTX 50 Series** | Original NVIDIA-signed DLSS NR 310.8.0 |
| **RTX 40 Series** | Project-tested RTX 40 compatibility DLSS NR 310.8.0 |

After install, open in-game:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

> **Keep GTA IV's own resolution set to your display's native resolution.** DLSS changes the internal render resolution separately.

## Prerequisites

| Requirement | Recommendation |
|---|---|
| **GTA IV: Complete Edition** | Clean game install before FusionFix. |
| **FusionFix** | [Install from the official repo](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix). |
| **NVIDIA driver** | [Install a current driver](https://www.nvidia.com/en-us/drivers/). Neural Rendering requires a DLSS 5-capable driver. |

**Git, Python, Visual Studio Build Tools and manual ReShade installation are not required.** The release installers use hash-verified prebuilt binaries.

## In-game controls

`Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS`

- DLAA Native
- Custom Ultra Quality 77%
- Quality
- Balanced
- Performance
- Ultra Performance
- Neural Rendering ON/OFF
- NR passes
- master DLSS/DLAA/NR processing toggle
- diagnostics

Defaults: **Quality**, Neural Rendering **OFF**, **1** NR pass.

## Uninstall

To remove **DLSS Full only** and return to DLAA, run `Uninstall-DLSS-Full.bat` from the GTA IV folder.

To remove **everything installed by this project** and return to the exact GTA IV + FusionFix state from before Step 2, right-click **`install/Uninstall-DLAA.bat` → Run as administrator**, enter the GTA IV folder, and confirm.

FusionFix itself is not removed.

## Troubleshooting

Main runtime log:

```text
GTAIV\.trex\dlss5-feed.log
```

`DLSS-Full-Control.bat` is for launch, repair, status and logs. Normal settings belong in ReShade.

Useful docs: [DLSS Full](docs/DLSS-FULL.md) · [Verification](docs/VERIFY.md) · [ReShade input patch](docs/RESHade-INPUT-PATCH.md)

## Credits

[FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) · [b-bridge](https://github.com/gutbash/b-bridge) · [DXVK](https://github.com/doitsujin/dxvk) · [ReShade](https://reshade.me/) · [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) · [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX)

Exact pinned versions and hashes are in [`manifests/versions.json`](manifests/versions.json).
