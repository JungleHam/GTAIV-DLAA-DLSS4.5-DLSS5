# v1.0.0

This is the first public release of the GTA IV DLAA / DLSS integration.

## Download

Open the repository's **Releases** page and download `GTAIV-DLSS-Setup.exe` from the v1.0.0 release.

https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases

The release page may also contain backend payloads used automatically by setup. Users should not manually place those payloads into GTA IV.

## Guided prerequisites

The cleaned installer source contains no direct third-party ZIP/EXE/DLL URLs. For each user-supplied prerequisite, setup explains the exact GitHub page and the exact buttons/filename to use.

See [`PREREQUISITES.md`](PREREQUISITES.md) for the same click-by-click guide:

- FusionFix 5.0.1 — FusionFix GitHub → right sidebar **Releases** → v5.0.1 → **Assets** → `GTAIV.EFLC.FusionFix.zip`; setup installs the ZIP for the user;
- ReShade 6.8.0 Full Add-On Support — ReShade GitHub → About → project website → official Full Add-On Support download;
- LumeniteFX — pinned GitHub commit → Code → Download ZIP;
- Full DLSS only — open `RankFTW/rhi-repo` (not `RankFTW/RHI`) → right sidebar **Releases** → use **Next** through older release pages until the exact GPU-specific 310.8.0 tag appears → **Assets** → exact ZIP. Users keep the ZIP beside setup and do not extract it.

Users are instructed to keep the setup EXE and every prerequisite download in one temporary folder. They do not manually install or extract prerequisites; setup validates and handles them.

## Modes

- **DLAA** — native-resolution DLAA baseline, ReShade/Lumenite temporal data and the b-bridge input patch.
- **Full DLSS** — DLAA plus DLSS 4.5 Super Resolution and optional DLSS 5 Neural Rendering.

Full DLSS automatically establishes the DLAA foundation first when necessary.

## Removal

The unified setup can remove Full DLSS only or remove the whole project integration. Full project removal restores the official ReShade DLL that existed before the project's input patch; FusionFix and the official ReShade installation remain installed.

Thanks to **FusionFix, b-bridge, DXVK, ReShade, DLSS5-Feeder, LumeniteFX and NVIDIA DLSS** for the projects and technology this integration builds on.
