# Prerequisite download guide — beginner version

This is the same guidance the future release installer is intended to show on screen. It assumes the user may never have used GitHub Releases before.

The repository stores **no direct third-party binary/archive download links**. Every hyperlink in this document starts on GitHub.

## First: make one setup-files folder

Create one temporary folder somewhere easy to find, for example:

```text
Desktop\GTA IV DLSS Setup Files\
```

Put `GTAIV-DLSS-Setup.exe` in that folder. Every prerequisite you download should go into **that same folder**.

Do not install or extract prerequisites yourself. Leave the downloaded ZIP/EXE files untouched. The setup validates and handles them.

For a fresh Full DLSS install the folder will normally contain:

```text
GTAIV-DLSS-Setup.exe
GTAIV.EFLC.FusionFix.zip          <- only if FusionFix is missing
ReShade_Setup_6.8.0_Addon.exe
LumeniteFX-....zip
nvngx_dlssnr_310.8.0-....zip
```

The installer tries to recognize the normal filenames automatically when they are beside the setup EXE.

## FusionFix 5.0.1

Start here: <https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix>

1. On the repository page, look at the **right-hand sidebar**.
2. Click **Releases**.
3. Open **GTAIV.EFLC.FusionFix v5.0.1**.
4. Find **Assets** and expand it if necessary.
5. Download `GTAIV.EFLC.FusionFix.zip`.
6. Put the ZIP beside `GTAIV-DLSS-Setup.exe`.
7. **Do not extract it.** Our setup installs it.

Expected SHA256:

```text
3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41
```

If setup installs FusionFix, it will stop before installing DLAA/DLSS. Launch GTA IV normally once, wait for the main menu, close the game, then rerun the same setup EXE from the same folder. Nothing else needs to be installed manually.

## ReShade 6.8.0 Full Add-On Support

Start here: <https://github.com/crosire/reshade>

ReShade does not publish the setup EXE as a GitHub Release.

1. On the GitHub repository page, find the **About** box on the right.
2. Click the official project website displayed in that box.
3. On the official ReShade page, scroll to **Download**.
4. Download **ReShade 6.8.0 with full add-on support**.
5. Put the downloaded EXE beside `GTAIV-DLSS-Setup.exe`.
6. **Do not run the ReShade EXE yourself.** Our setup verifies it and runs it with the correct GTA IV bridge target.

Expected SHA256:

```text
AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445
```

## LumeniteFX

Start at the pinned commit: <https://github.com/umar-afzaal/LumeniteFX/tree/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9>

1. Click the green **Code** button.
2. Click **Download ZIP**.
3. Put that ZIP beside `GTAIV-DLSS-Setup.exe`.
4. **Do not extract it.** Our setup extracts the required files.

Expected ZIP SHA256:

```text
43220F99FC0FFA0216E01EBD657180F8C9D043C939F760283B896EA257F1B6A2
```

## DLSS Neural Rendering runtime — Full DLSS only

Start here: <https://github.com/RankFTW/rhi-repo>

### First make sure you are in the correct repository

The repository name at the top must say:

```text
RankFTW / rhi-repo
```

There is also a different repository named `RankFTW / RHI`. **That is not the release list used by this project.**

### How to reach the older NR releases

1. On `RankFTW/rhi-repo`, look at the **right-hand sidebar**.
2. Click **Releases**.
3. GitHub opens a long release list. The package we need is older, so **do not use the newest release**.
4. Scroll to the bottom of the release list and click **Next** to move to an older page.
5. Continue clicking **Next** until the exact 310.8.0 release below appears. You will often need to click Next a couple of times. The number is not fixed because new releases can push old ones farther back.
6. If you see a **Find a release** box, you can try the exact search text below. If it does not immediately show the release, continue using **Next** through the older pages.
7. Open the exact matching release.
8. Find **Assets**.
9. Download the exact ZIP name shown below.
10. Put the ZIP beside `GTAIV-DLSS-Setup.exe`.
11. **Do not extract it.** Our setup validates the archive, extracts `nvngx_dlssnr.dll`, and verifies the DLL.

### RTX 40 Series

Exact release/tag:

```text
dlssnr-310.8.0-RTX40
```

Asset to download:

```text
nvngx_dlssnr_310.8.0-RTX40.zip
```

ZIP SHA256:

```text
46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F
```

Extracted DLL SHA256 expected by setup:

```text
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

This is the tested modded RTX 40 compatibility build.

### RTX 50 Series

Exact release/tag:

```text
dlssnr-310.8.0
```

Do **not** choose the release ending in `-RTX40`.

Asset to download:

```text
nvngx_dlssnr_310.8.0.zip
```

ZIP SHA256:

```text
388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC
```

Extracted DLL SHA256 expected by setup:

```text
E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

The RTX 50 DLL must also retain a valid NVIDIA Authenticode signature.

## What setup handles automatically

A release user does not need Git, Python, Visual Studio, b-bridge, DXVK, DLSS5-Feeder, ReShade headers, or the normal DLSS SR/DLAA DLL.

The user only collects the prerequisite files into one folder. The setup handles validation, extraction, file placement and the official ReShade invocation.
