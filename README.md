# GTA IV — DLAA + DLSS 4.5 + DLSS 5 Neural Rendering

A guided DLAA / DLSS stack for **GTA IV: Complete Edition**.

Tested release target: **RTX 4070 Ti SUPER at 2560×1440**.

> **Current source status:** the repository/source cleanup is complete, but the cleaned installer/runtime has intentionally **not been rebuilt yet**. Do not republish the old installer as the cleaned release.
>
> **Link policy:** every hyperlink stored in this repository points to GitHub. There are no direct third-party ZIP/EXE/DLL download links in the repository.

## The easy way to prepare

Before running the future cleaned installer, make **one temporary folder** somewhere easy to find, for example:

```text
Desktop\GTA IV DLSS Setup Files\
```

Put **`GTAIV-DLSS-Setup.exe` and every prerequisite file you download into that same folder**.

Example for a fresh Full DLSS install:

```text
GTA IV DLSS Setup Files\
├── GTAIV-DLSS-Setup.exe
├── GTAIV.EFLC.FusionFix.zip        (only if FusionFix is not already installed)
├── ReShade_Setup_6.8.0_Addon.exe
├── LumeniteFX-....zip
└── nvngx_dlssnr_310.8.0-....zip
```

**Do not install or extract those files yourself.**

- Do **not** extract FusionFix.
- Do **not** run the ReShade installer yourself.
- Do **not** extract LumeniteFX.
- Do **not** extract the DLSS Neural Rendering ZIP.
- Do **not** copy any of them into the GTA IV folder manually.

The future `GTAIV-DLSS-Setup.exe` validates and installs/extracts them for you. If the files use their normal names and are beside the setup EXE, setup tries to find them automatically.

The only unavoidable manual step is this: if setup installs FusionFix for you, **launch GTA IV normally once, wait until the main menu appears, close the game, then run `GTAIV-DLSS-Setup.exe` again from the same setup-files folder**. This is required so FusionFix can complete its first-run initialization.

## What you may need to download

| File | When needed | Start here |
|---|---|---|
| **FusionFix 5.0.1 ZIP** | Only if FusionFix is not already installed | [ThirteenAG/GTAIV.EFLC.FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) |
| **ReShade 6.8.0 Full Add-On Support installer** | Fresh DLAA / fresh Full install | [crosire/reshade](https://github.com/crosire/reshade) |
| **Pinned LumeniteFX ZIP** | Fresh DLAA / fresh Full install | [Pinned LumeniteFX commit](https://github.com/umar-afzaal/LumeniteFX/tree/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9) |
| **DLSS Neural Rendering ZIP** | Full DLSS only | [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo) |

You do **not** need to find b-bridge, DLSS5-Feeder, DXVK/presenter files, the normal `nvngx_dlss.dll`, ReShade headers, or project-built DLLs. Those are handled by the project runtime.

## Exactly how to download each prerequisite

### 1. FusionFix 5.0.1

Open [ThirteenAG/GTAIV.EFLC.FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix).

1. Look at the **right side** of the GitHub repository page.
2. Click **Releases**.
3. Open **GTAIV.EFLC.FusionFix v5.0.1**.
4. Find **Assets**. If it is collapsed, click it to expand it.
5. Download **`GTAIV.EFLC.FusionFix.zip`**.
6. Save the ZIP into your **GTA IV DLSS Setup Files** folder beside `GTAIV-DLSS-Setup.exe`.
7. **Do not extract it.** Setup installs it for you.

Expected ZIP SHA256:

```text
3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41
```

If FusionFix was missing, setup installs it first and then stops. Launch GTA IV once to the main menu, close it, and rerun the same setup EXE from the same folder.

### 2. ReShade 6.8.0 — Full Add-On Support

Open [crosire/reshade](https://github.com/crosire/reshade).

The official ReShade installer itself is not published as a GitHub Release, so follow the official project route:

1. On the ReShade GitHub page, look at the **About** box on the right.
2. Click the project website shown inside that GitHub About box.
3. On the official ReShade page, go to **Download**.
4. Choose **ReShade 6.8.0 with full add-on support** — not the normal build.
5. Save the downloaded EXE into your **GTA IV DLSS Setup Files** folder beside our setup EXE.
6. **Do not run ReShade yourself.** Our setup runs it with the correct target and options.

Expected setup SHA256:

```text
AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445
```

### 3. LumeniteFX

Open the exact pinned source tree:

[LumeniteFX commit `f8cbbb4...`](https://github.com/umar-afzaal/LumeniteFX/tree/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9)

1. Click the green **Code** button.
2. Click **Download ZIP**.
3. Save the ZIP into your **GTA IV DLSS Setup Files** folder.
4. **Do not extract it.** Our setup does that for you.

Expected archive SHA256:

```text
43220F99FC0FFA0216E01EBD657180F8C9D043C939F760283B896EA257F1B6A2
```

### 4. DLSS 5 Neural Rendering — Full DLSS only

This is the prerequisite most likely to confuse a new GitHub user, so follow these steps literally.

Start at **this repository**:

[RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo)

**Make sure the repository name at the top says `RankFTW / rhi-repo`. Do not use the separate `RankFTW / RHI` repository.**

Then:

1. Look at the **right-hand side** of the `RankFTW/rhi-repo` repository page.
2. Click **Releases**.
3. You will see a long list of releases. **Do not download the newest one.** Our project uses an older, tested 310.8.0 package.
4. If the release you need is not on the first page, scroll to the bottom of the Releases list and click **Next** to show older releases.
5. Keep clicking **Next** until you reach the exact release listed for your GPU below. You may need to click Next a couple of times. The exact number can change whenever newer releases are added.
6. If GitHub shows a **Find a release** box, you can also type the exact release/tag name below. If that does not immediately show it, continue through the older release pages with **Next**.
7. Open the exact release, find **Assets**, and download the exact ZIP filename shown below.
8. Save that ZIP beside `GTAIV-DLSS-Setup.exe` in your setup-files folder.
9. **Do not extract the ZIP.** Our setup validates and extracts it.

The installer automatically detects whether you have an RTX 40 or RTX 50 Series GPU and repeats the correct instructions on screen.

#### RTX 40 Series

Find this **exact** release/tag:

```text
dlssnr-310.8.0-RTX40
```

Then under **Assets** download:

```text
nvngx_dlssnr_310.8.0-RTX40.zip
```

Expected archive SHA256:

```text
46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F
```

Expected DLL SHA256 after setup extracts it:

```text
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

This is the project-tested **modded RTX 40 compatibility** Neural Rendering DLL.

#### RTX 50 Series

Find this **exact** release/tag:

```text
dlssnr-310.8.0
```

**Do not choose `dlssnr-310.8.0-RTX40`.** RTX 50 uses the plain 310.8.0 release.

Under **Assets** download:

```text
nvngx_dlssnr_310.8.0.zip
```

Expected archive SHA256:

```text
388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC
```

Expected DLL SHA256 after setup extracts it:

```text
E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

The RTX 50 DLL must also have a valid NVIDIA Authenticode signature.

> Newer Neural Rendering packages may exist. **Do not substitute a newer package unless this project explicitly updates its tested version.**

## Future installer flow

After the cleaned installer is eventually built:

1. Download `GTAIV-DLSS-Setup.exe` from this project's GitHub Releases page.
2. Make the temporary setup-files folder described above and move the setup EXE into it.
3. Run the setup EXE as Administrator.
4. Select the folder containing `GTAIV.exe`.
5. Choose **DLAA** or **Full DLSS**.
6. Setup tells you exactly which prerequisite is missing, opens only the corresponding GitHub project page, and tells you which buttons to press.
7. Put every downloaded prerequisite beside the setup EXE. Do not install/extract it yourself.
8. Setup validates the files and handles installation automatically.

Project releases: <https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases>

## Install modes

| Mode | What it installs |
|---|---|
| **DLAA** | Native-resolution DLAA + ReShade + Lumenite temporal data + b-bridge input patch |
| **Full DLSS** | Everything in DLAA + DLSS 4.5 Super Resolution + optional DLSS 5 Neural Rendering |

Full DLSS is currently guided for **RTX 40 and RTX 50 Series** GPUs because those two tested NR paths use different packages. If setup cannot identify an RTX 40/50 GPU, Full DLSS stops before the NR download step; DLAA remains available.

The normal DLSS 4.5 / DLAA `nvngx_dlss.dll` 310.9.1 comes from [NVIDIA/DLSS](https://github.com/NVIDIA/DLSS) as part of the project runtime. Users do not locate it themselves.

Neural Rendering is installed but starts **OFF** by default.

## In-game controls

Press **Home**, then open:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

Available controls include DLAA Native, Ultra Quality 77%, Quality, Balanced, Performance, Ultra Performance, Neural Rendering, NR pass count, master processing, and diagnostics.

> Keep GTA IV's own display resolution set to your monitor's native resolution. DLSS manages its internal render resolution separately.

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

## Credits

[FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) · [b-bridge](https://github.com/gutbash/b-bridge) · [DXVK](https://github.com/doitsujin/dxvk) · [ReShade](https://github.com/crosire/reshade) · [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) · [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX) · [NVIDIA DLSS](https://github.com/NVIDIA/DLSS)

Pinned versions and hashes: [`manifests/versions.json`](manifests/versions.json).
