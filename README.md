# GTA IV — DLAA + DLSS 4.5 + DLSS 5 Neural Rendering

A guided DLAA / DLSS stack for **GTA IV: Complete Edition**.

Tested release target: **RTX 4070 Ti SUPER at 2560×1440**.

> **Current source status:** the GitHub-clean installer source is ready, but the cleaned runtime and installer binary have **not been rebuilt/published yet**.
>
> **Link policy:** every hyperlink stored in this repository points to GitHub. There are no direct third-party ZIP/EXE/DLL download links in the repository.

## Installation — all steps in order

This is the whole flow. Detailed notes follow underneath.

1. Download **`GTAIV-DLSS-Setup.exe`** from this project's [GitHub Releases](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases).
2. Run it as Administrator and select the folder containing **`GTAIV.exe`**.
3. Choose **DLAA** or **Full DLSS**.
4. Setup automatically downloads and verifies GitHub-hosted dependencies:
   - [FusionFix 5.0.1](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix), if missing;
   - pinned [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX);
   - for Full DLSS, the GPU-matched NR package from [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo);
   - this project's runtime and input patch.
5. If FusionFix was just installed, launch GTA IV once to the main menu, close it, then run setup again.
6. On a fresh DLAA foundation, setup asks for **ReShade 6.8.0 Full Add-On Support**. Open [crosire/reshade on GitHub](https://github.com/crosire/reshade), use the official website shown in its **About** box, download the **6.8.0 full add-on support** installer, then select that EXE in setup. **Do not run ReShade yourself.**
7. Continue setup. For Full DLSS, the installer shows the detected RTX series inside the wizard, downloads the correct NR package automatically, and installs NR **OFF by default**.

That is it. **ReShade is the only dependency you may need to download manually.**

## What setup downloads automatically

| Component | Source |
|---|---|
| FusionFix 5.0.1 | [ThirteenAG/GTAIV.EFLC.FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) |
| Pinned LumeniteFX | [umar-afzaal/LumeniteFX](https://github.com/umar-afzaal/LumeniteFX) |
| DLSS NR 310.8.0 for RTX 40/50 | [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo) |
| Standard DLSS runtime | [NVIDIA/DLSS](https://github.com/NVIDIA/DLSS) |
| Project runtime / input patch | [this repository](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5) |

The installer resolves release assets through GitHub, downloads them itself, and verifies the pinned SHA256 values before using them.

## Step 1 — Choose GTA IV and install mode

Run `GTAIV-DLSS-Setup.exe` as Administrator.

Select the GTA IV folder containing:

```text
GTAIV.exe
```

Then choose:

| Mode | Result |
|---|---|
| **DLAA** | Native-resolution DLAA + ReShade + Lumenite temporal data + b-bridge input patch |
| **Full DLSS** | Everything above + DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering |

## Step 2 — FusionFix

If FusionFix is missing, setup automatically obtains **FusionFix 5.0.1** from [ThirteenAG/GTAIV.EFLC.FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix), validates it, and installs it.

Expected ZIP SHA256:

```text
3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41
```

After a new FusionFix installation, setup stops intentionally.

Launch GTA IV normally once, wait for the main menu, close the game, then run setup again. This first run is required before the DLAA/DLSS stage.

## Step 3 — ReShade 6.8.0 Full Add-On Support

This is the only manual download in the normal flow.

Open [crosire/reshade](https://github.com/crosire/reshade).

1. In the GitHub **About** box, open the official project website.
2. Find **ReShade 6.8.0 with full add-on support**.
3. Download that installer, not the normal build.
4. Select the downloaded EXE in our setup.
5. **Do not run ReShade yourself.**

Expected setup SHA256:

```text
AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445
```

Setup runs ReShade against the correct Vulkan bridge target automatically.

## Step 4 — Full DLSS GPU / Neural Rendering

For **Full DLSS**, GPU detection is shown directly inside the installer.

### RTX 40 Series

Setup displays:

```text
Detected: RTX 40 Series
DLSS NR: 310.8.0 RTX 40 compatibility build
Source: RankFTW/rhi-repo on GitHub
Setup will download and verify it automatically.
Neural Rendering starts OFF.
```

The package is resolved from [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo) using the exact pinned release:

```text
dlssnr-310.8.0-RTX40
nvngx_dlssnr_310.8.0-RTX40.zip
```

### RTX 50 Series

Setup uses the original NVIDIA-signed 310.8.0 package from the same [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo) catalog:

```text
dlssnr-310.8.0
nvngx_dlssnr_310.8.0.zip
```

You do not browse old release pages or select the ZIP manually anymore.

## Step 5 — What setup installs

Setup automatically handles:

- FusionFix installation when needed;
- pinned LumeniteFX download and extraction;
- GPU-matched NR download and validation for Full DLSS;
- official ReShade installation against `.trex\NvRemixBridge.exe`;
- project runtime installation;
- DLSS5-Feeder;
- official NVIDIA `nvngx_dlss.dll` for DLAA/DLSS 4.5;
- custom DXVK/presenter and bridge files;
- the b-bridge ReShade input patch;
- rollback backups.

All stored repository hyperlinks remain GitHub links. ReShade's off-GitHub installer location is described via the official website linked from the ReShade GitHub repository rather than embedded directly.

## First launch and defaults



Keep GTA IV's normal display resolution set to your monitor's native resolution.

### DLAA install

DLAA is active at native resolution after installation.

### Full DLSS install

The first completed Full DLSS launch starts with:

```text
DLSS profile: Quality
Neural Rendering: OFF
NR passes when enabled: 1
startup stabilization: 1485×835 for 180 valid synchronized frames
```

**NR is installed but intentionally OFF on the first Full DLSS launch.** This lets the user verify the base DLSS 4.5 path first.

To enable NR later, press **Home** and open:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

## In-game controls

Press **Home**, then open:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

Available controls include DLAA Native, Ultra Quality 77%, Quality, Balanced, Performance, Ultra Performance, Neural Rendering, NR pass count, master processing, and diagnostics.

## Remove or modify

Run `GTAIV-DLSS-Setup.exe` again and choose:

- **Remove DLSS Full only** — keeps the DLAA/ReShade foundation.
- **Remove everything from this project** — restores the saved GTA IV + FusionFix baseline and restores the official ReShade DLL preserved before the input patch. FusionFix itself remains installed.

## Known limitation

Steam's built-in FPS counter may disappear while a **DLSS Super Resolution** profile is active. It remains visible in **DLAA Native** and with project processing **OFF**. This is an overlay-display limitation; DLSS and Neural Rendering continue to operate normally.

## Troubleshooting

Main runtime log:

```text
GTAIV\.trex\dlss5-feed.log
```

Documentation: [Prerequisites](docs/PREREQUISITES.md) · [DLAA](docs/DLAA.md) · [Full DLSS](docs/DLSS-FULL.md) · [Verification](docs/VERIFY.md) · [ReShade input patch](docs/RESHade-INPUT-PATCH.md) · [Third-party policy](docs/THIRD-PARTY.md)

Project releases: <https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases>

## Credits

[FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) · [b-bridge](https://github.com/gutbash/b-bridge) · [DXVK](https://github.com/doitsujin/dxvk) · [ReShade](https://github.com/crosire/reshade) · [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) · [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX) · [NVIDIA DLSS](https://github.com/NVIDIA/DLSS)

Pinned versions and hashes: [`manifests/versions.json`](manifests/versions.json).
