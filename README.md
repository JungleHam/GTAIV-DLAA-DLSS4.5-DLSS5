# GTA IV — DLAA + DLSS 4.5 + DLSS 5 Neural Rendering

A guided DLAA / DLSS stack for **GTA IV: Complete Edition**.

Tested release target: **RTX 4070 Ti SUPER at 2560×1440**.

> **Current source status:** the GitHub-clean installer source is ready, but the cleaned runtime and installer binary have **not been rebuilt/published yet**.
>
> **Link policy:** every hyperlink stored in this repository points to GitHub. There are no direct third-party ZIP/EXE/DLL download links in the repository.

## Installation — all steps in order

This is the entire install process from start to finish. Detailed instructions for every download are further down.

1. Create one temporary folder somewhere easy to find, for example:
   ```text
   Desktop\GTA IV DLSS Setup Files\
   ```
2. Download **`GTAIV-DLSS-Setup.exe`** from this project's [GitHub Releases page](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases) and put it in that folder.
3. Run the setup EXE as Administrator and select the folder containing **`GTAIV.exe`**.
4. Choose **Install / repair DLAA** or **Install / repair Full DLSS**.
5. If FusionFix is missing, open [ThirteenAG/GTAIV.EFLC.FusionFix on GitHub](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix). On the right side click **Releases**, open **GTAIV.EFLC.FusionFix v5.0.1**, expand **Assets**, and download **`GTAIV.EFLC.FusionFix.zip`**. Put the ZIP beside the setup EXE. **Do not extract it.**
6. Run setup again if needed. Setup installs FusionFix for you. If FusionFix was just installed, launch GTA IV normally once, wait for the main menu, close the game, then run the same setup EXE again.
7. For a fresh DLAA or Full install, collect two prerequisites:
   - **ReShade 6.8.0 with Full Add-On Support** — start at [crosire/reshade on GitHub](https://github.com/crosire/reshade). In the GitHub **About** box, click the official project website shown there; on that site look for **ReShade 6.8.0 with full add-on support**. Do not use the normal build.
   - **LumeniteFX ZIP** — open the [pinned LumeniteFX commit on GitHub](https://github.com/umar-afzaal/LumeniteFX/tree/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9), then click **Code → Download ZIP**.
   Put both downloaded files beside the setup EXE. **Do not install or extract either one yourself.**
8. If you chose **Full DLSS**, open [RankFTW/rhi-repo on GitHub](https://github.com/RankFTW/rhi-repo). Setup detects whether the GPU is RTX 40 or RTX 50 and tells you the exact **DLSS Neural Rendering 310.8.0** release/tag and ZIP filename to find. On GitHub click **Releases** in the right sidebar, then use **Next** through older release pages until the exact tag appears. Put that ZIP beside the setup EXE. **Do not extract it.**
9. Continue setup. It validates the prerequisite files, installs ReShade itself, extracts the required packages, downloads the project's own runtime from [this GitHub repository](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5), applies the b-bridge ReShade input patch, and finishes the selected mode automatically.
10. Launch GTA IV.
    - **DLAA:** DLAA is ready immediately.
    - **Full DLSS:** initial DLSS profile is **Quality**. **Neural Rendering is installed but starts OFF on the first launch.** Enable it later from the ReShade Add-ons panel if wanted.

**Do not manually install, extract, or copy prerequisite files into GTA IV.** Keep all downloaded prerequisite files beside `GTAIV-DLSS-Setup.exe` and let setup handle them.

## What you may need to download

| File | When needed | Start here |
|---|---|---|
| **FusionFix 5.0.1 ZIP** | Only if FusionFix is not already installed | [ThirteenAG/GTAIV.EFLC.FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) |
| **ReShade 6.8.0 Full Add-On Support installer** | Fresh DLAA / fresh Full install | [crosire/reshade](https://github.com/crosire/reshade) |
| **Pinned LumeniteFX ZIP** | Fresh DLAA / fresh Full install | [Pinned LumeniteFX commit](https://github.com/umar-afzaal/LumeniteFX/tree/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9) |
| **DLSS Neural Rendering ZIP** | Full DLSS only | [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo) |

You do **not** need to find b-bridge, DLSS5-Feeder, DXVK/presenter files, the normal `nvngx_dlss.dll`, ReShade headers, or project-built DLLs. Those are handled by the project runtime.

## Step 1 — Make the setup-files folder

Create one temporary folder, for example:

```text
Desktop\GTA IV DLSS Setup Files\
```

Put `GTAIV-DLSS-Setup.exe` there. Every prerequisite you download should go into this same folder.

A fresh Full DLSS setup will usually end up looking like:

```text
GTA IV DLSS Setup Files\
├── GTAIV-DLSS-Setup.exe
├── GTAIV.EFLC.FusionFix.zip        (only if FusionFix was missing)
├── ReShade_Setup_6.8.0_Addon.exe
├── LumeniteFX-....zip
└── nvngx_dlssnr_310.8.0-....zip
```

Leave those files untouched. Setup recognizes the normal filenames automatically where possible.

## Step 2 — FusionFix 5.0.1

If FusionFix is already installed and has been run once, setup skips this step.

Otherwise open [ThirteenAG/GTAIV.EFLC.FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix).

1. Look at the **right-hand side** of the GitHub repository page.
2. Click **Releases**.
3. Open **GTAIV.EFLC.FusionFix v5.0.1**.
4. Find **Assets** and expand it if necessary.
5. Download **`GTAIV.EFLC.FusionFix.zip`**.
6. Save it beside `GTAIV-DLSS-Setup.exe`.
7. **Do not extract it.**

Expected ZIP SHA256:

```text
3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41
```

Setup installs FusionFix itself. After that first installation, launch GTA IV normally once, wait until the main menu appears, close the game, and rerun `GTAIV-DLSS-Setup.exe` from the same setup-files folder.

That GTA IV launch is the only unavoidable manual first-run step.

## Step 3 — ReShade 6.8.0 Full Add-On Support

Open [crosire/reshade](https://github.com/crosire/reshade).

The official ReShade installer is not published as a GitHub Release, so use the official project route:

1. On the ReShade GitHub page, find the **About** box on the right.
2. Click the official project website shown in that box.
3. On the official ReShade page, go to **Download**.
4. Download **ReShade 6.8.0 with full add-on support** — not the normal build.
5. Save the EXE beside `GTAIV-DLSS-Setup.exe`.
6. **Do not run ReShade yourself.** Our setup verifies it and runs it against the correct bridge target.

Expected setup SHA256:

```text
AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445
```

## Step 4 — LumeniteFX

Open the exact pinned tree:

[LumeniteFX commit `f8cbbb4...`](https://github.com/umar-afzaal/LumeniteFX/tree/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9)

1. Click the green **Code** button.
2. Click **Download ZIP**.
3. Save the ZIP beside `GTAIV-DLSS-Setup.exe`.
4. **Do not extract it.**

Expected archive SHA256:

```text
43220F99FC0FFA0216E01EBD657180F8C9D043C939F760283B896EA257F1B6A2
```

Setup extracts only the required LumeniteFX files into the ReShade shader folders.

## Step 5 — Choose DLAA or Full DLSS

Run `GTAIV-DLSS-Setup.exe`, select the GTA IV folder and choose one of:

| Mode | What it installs |
|---|---|
| **DLAA** | Native-resolution DLAA + ReShade + Lumenite temporal data + b-bridge input patch |
| **Full DLSS** | Everything in DLAA + DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering runtime |

For DLAA, there is no NR download step.

For Full DLSS, continue with Step 6.

## Step 6 — DLSS 5 Neural Rendering package — Full DLSS only

The installer automatically detects whether the GPU is RTX 40 or RTX 50 and repeats the correct instructions on screen.

Start here:

[RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo)

**Check the repository name at the top. It must say `RankFTW / rhi-repo`. Do not use the separate `RankFTW / RHI` repository.**

Then:

1. On the **right-hand side** of the repository page, click **Releases**.
2. You will see a long list. **Do not download the newest release.** This project uses a specific older 310.8.0 package.
3. Scroll to the bottom of the Releases page.
4. Click **Next** to show older releases.
5. Keep clicking **Next** until the exact release for your GPU appears. You may need to press Next a couple of times; the exact number changes as newer releases are added.
6. If GitHub shows a **Find a release** box, you can type the exact release/tag below. If it does not immediately find it, keep using **Next**.
7. Open the exact release.
8. Expand **Assets**.
9. Download the exact ZIP listed below.
10. Put the ZIP beside `GTAIV-DLSS-Setup.exe`.
11. **Do not extract it.**

### RTX 40 Series

Find this exact release/tag:

```text
dlssnr-310.8.0-RTX40
```

Under **Assets**, download:

```text
nvngx_dlssnr_310.8.0-RTX40.zip
```

Expected archive SHA256:

```text
46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F
```

Expected extracted DLL SHA256:

```text
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

This is the project-tested **modded RTX 40 compatibility** Neural Rendering DLL.

### RTX 50 Series

Find this exact release/tag:

```text
dlssnr-310.8.0
```

**Do not choose `dlssnr-310.8.0-RTX40`.**

Under **Assets**, download:

```text
nvngx_dlssnr_310.8.0.zip
```

Expected archive SHA256:

```text
388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC
```

Expected extracted DLL SHA256:

```text
E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

The RTX 50 DLL must also retain a valid NVIDIA Authenticode signature.

> Newer Neural Rendering packages may exist. **Do not substitute a newer package unless this project explicitly updates its tested version.**

## Step 7 — Let setup install everything

Once the required files are beside the setup EXE, continue through setup.

Setup handles:

- prerequisite SHA256 validation;
- FusionFix ZIP extraction when FusionFix is missing;
- official ReShade installation against `.trex\NvRemixBridge.exe`;
- LumeniteFX extraction;
- project runtime installation;
- DLSS5-Feeder;
- official NVIDIA `nvngx_dlss.dll` 310.9.1 for DLAA/DLSS 4.5;
- custom DXVK/presenter and bridge files;
- the b-bridge ReShade input patch;
- Full DLSS NR package extraction and GPU-specific validation;
- backups required for later removal/rollback.

The normal DLSS 4.5 / DLAA `nvngx_dlss.dll` comes from [NVIDIA/DLSS](https://github.com/NVIDIA/DLSS) as part of the project runtime. Users do not locate it themselves.

## Step 8 — First launch and defaults

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
