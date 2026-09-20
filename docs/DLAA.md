# DLAA installation

## Purpose

DLAA establishes the native-resolution temporal baseline used by the project before Super Resolution and Neural Rendering are added.

## Beginner preparation

Create one temporary folder such as:

```text
Desktop\GTA IV DLSS Setup Files\
```

Keep `GTAIV-DLSS-Setup.exe` and every prerequisite download in that folder. **Do not manually install or extract any prerequisite.** See [`PREREQUISITES.md`](PREREQUISITES.md) for the exact GitHub clicks.

For a fresh DLAA setup you may need:

- [`GTAIV.EFLC.FusionFix.zip`](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) if FusionFix is not already installed — use the repository's **Releases** section;
- official ReShade 6.8.0 **Full Add-On Support** setup EXE — start at [crosire/reshade on GitHub](https://github.com/crosire/reshade), then use the official website shown in the GitHub **About** box and look for the Full Add-On Support build;
- official LumeniteFX ZIP from the [pinned commit on GitHub](https://github.com/umar-afzaal/LumeniteFX/tree/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9) — use **Code → Download ZIP**.

Setup installs/extracts these itself. If it installs FusionFix, it will ask you to launch GTA IV normally once to the main menu, close it, then rerun setup from the same folder. That first game launch is required by FusionFix; there is no other manual install step.

## Install

Run `GTAIV-DLSS-Setup.exe` as Administrator, select the GTA IV folder, and choose **Install / repair DLAA**.

Setup validates the local prerequisite files. It runs the official ReShade installer against the bridge renderer itself, extracts LumeniteFX, and installs the project runtime. Do **not** run ReShade or unpack LumeniteFX yourself.

The project runtime supplies the pinned b-bridge/DXVK integration, DLSS5-Feeder pieces, ReShade headers, and NVIDIA `nvngx_dlss.dll` 310.9.1.

After official ReShade installs its Vulkan layer, the project applies its b-bridge input-patched ReShade DLL so the Home key, keyboard and mouse work with the 64-bit bridge renderer. The official DLL is backed up for restoration during project removal.

## Known-good baseline

FusionFix:

```ini
[MAIN]
GraphicsAPI=0
Windowed=1
BorderlessWindowed=1

[MISC]
Antialiasing=5

[FRAMELIMIT]
FpsLimitPreset=0
```

DLSS feeder:

```ini
enabled=1
mode=2
work_resolution=100
```

At this stage GTA IV still renders at native/output resolution. Super Resolution and Neural Rendering are not enabled by the DLAA-only mode.

## Verify

Launch GTA IV and inspect:

```text
GTAIV\.trex\dlss5-feed.log
```

Expected evidence includes the Lumenite motion-vector provider, successful DLAA feature creation and delivered frames. Press **Home** to confirm the ReShade overlay accepts keyboard and mouse input.
