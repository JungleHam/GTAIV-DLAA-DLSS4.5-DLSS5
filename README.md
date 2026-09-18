# GTA IV — DLAA + DLSS 4.5 + DLSS 5 Neural Rendering

A streamlined DLAA / DLSS stack for **GTA IV: Complete Edition**. Tested on **RTX 4070 Ti SUPER**.

## Install

1. Install [FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix), launch GTA IV once, then close it.
2. Download **[GTAIV-DLSS-Setup.exe](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases/download/v1.0.0/GTAIV-DLSS-Setup.exe)**.
3. Run it as **Administrator**, select the folder containing `GTAIV.exe`, then choose:

| Mode | Installs |
|---|---|
| **DLAA** | DLAA + ReShade 6.8 Add-On Support + input patch |
| **Full DLSS** | Everything above + DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering |

**Full DLSS automatically installs the DLAA foundation first.** Installation order cannot be wrong.

The setup also verifies that **FusionFix has completed its first run** before installation is allowed.

Run the same setup again later to **repair, upgrade, remove DLSS Full only, or remove everything from this project**.

> Keep GTA IV's own resolution set to your display's native resolution. DLSS changes the internal render resolution separately.

## Requirements

| Requirement | Recommendation |
|---|---|
| **GTA IV: Complete Edition** | Clean game install before FusionFix |
| **FusionFix** | [Official repo](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) |
| **NVIDIA driver** | [Current driver](https://www.nvidia.com/en-us/drivers/) |

**Git, Python, Visual Studio Build Tools and manual ReShade installation are not required.** Release assets are prebuilt and SHA256-verified before installation.

## Neural Rendering

| GPU | Runtime |
|---|---|
| **RTX 50 Series** | Original NVIDIA-signed DLSS NR 310.8.0 |
| **RTX 40 Series** | Project-tested RTX 40 compatibility DLSS NR 310.8.0 |

Neural Rendering starts **OFF**. DLSS defaults to **Quality** with **1 NR pass**.

## In-game controls

Press **Home**:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

Available: DLAA Native, Ultra Quality 77%, Quality, Balanced, Performance, Ultra Performance, Neural Rendering, NR passes, master DLSS/DLAA/NR toggle, and diagnostics.

## Remove / modify

Run **`GTAIV-DLSS-Setup.exe`** again and choose:

- **Remove DLSS Full only** → keeps DLAA + ReShade input patch.
- **Remove everything from this project** → restores the saved GTA IV + FusionFix baseline. FusionFix itself stays installed.

The BAT files under `install/` remain available as manual/fallback tools.

## Known limitation

Steam's built-in FPS counter currently sometimes disappears while a **DLSS Super Resolution** profile is active (Ultra Quality 77%, Quality, Balanced, Performance, or Ultra Performance). It remains visible in **DLAA Native** and with project processing **OFF**. This is an overlay-display limitation; DLSS and Neural Rendering continue to operate normally.

## Troubleshooting

Main runtime log:

```text
GTAIV\.trex\dlss5-feed.log
```

Useful docs: [DLSS Full](docs/DLSS-FULL.md) · [Verification](docs/VERIFY.md) · [ReShade input patch](docs/RESHade-INPUT-PATCH.md)

## Credits

[FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) · [b-bridge](https://github.com/gutbash/b-bridge) · [DXVK](https://github.com/doitsujin/dxvk) · [ReShade](https://reshade.me/) · [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) · [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX)

## Screenshots via links
https://i.vgy.me/753vlP.jpg
https://i.vgy.me/JREhV8.png
https://i.vgy.me/j9kHP6.png
https://i.vgy.me/j0aMuQ.png
https://i.vgy.me/WjlSqS.png
https://i.vgy.me/TT7EUv.png
https://i.vgy.me/UqrH0H.png
https://i.vgy.me/dvDNhv.png
https://i.vgy.me/un16lH.png
https://i.vgy.me/u0GPEF.png
https://i.vgy.me/ViatXJ.png
https://i.vgy.me/nPEmCe.png
https://i.vgy.me/8tDCQU.png
https://i.vgy.me/803Bsd.png
https://i.vgy.me/Tm7fCg.png

Pinned versions and hashes: [`manifests/versions.json`](manifests/versions.json).
