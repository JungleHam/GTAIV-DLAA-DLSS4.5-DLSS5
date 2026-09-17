# GTA IV DLAA + DLSS 4.5 + DLSS 5 Neural Rendering — v1.0.0

The first public release. One installer handles installation, repair, upgrades, and removal. 🎀

## Download

**Most users only need `GTAIV-DLSS-Setup.exe` from the Assets section below.**

The other release assets are verified support payloads used by the installer and are provided for transparency/reproducibility.

## What you get

- **DLAA Native** plus five DLSS Super Resolution profiles: Ultra Quality 77%, Quality, Balanced, Performance, and Ultra Performance.
- **DLSS 5 Neural Rendering** with live on/off control and adjustable pass count.
- **ReShade 6.8 Add-On Support** with the project's b-bridge input fix.
- A single **Setup & Maintenance** wizard: install/repair DLAA, install/repair Full DLSS, remove Full while keeping DLAA, or remove the whole project while keeping FusionFix.
- **FusionFix first-run detection** so the setup will not proceed until a clean FusionFix launch has initialized correctly.
- **Prebuilt, SHA256-verified runtime assets**. No Git, Python, Visual Studio, or local compilation is required.

## Before installing

1. Start from GTA IV: Complete Edition with **FusionFix** installed.
2. Launch GTA IV normally once, reach the menu, then quit normally.
3. Run `GTAIV-DLSS-Setup.exe` as Administrator and select the folder containing `GTAIV.exe`.
4. Keep GTA IV's own resolution set to your display's **native resolution**. The mod changes internal render resolution separately.

## In-game controls

Press **Home** and open:

`Add-ons → DLSS 5 Feed → GTA IV DLSS`

Neural Rendering defaults to **OFF** and DLSS defaults to **Quality**.

## Hardware validation

The complete public stack was hardware-tested on an **RTX 4070 Ti SUPER at 2560×1440**, including live DLAA/DLSS switching, Neural Rendering, startup stabilization, and the master processing toggle. The installer includes the RTX 40 compatibility NR path and the original NVIDIA-signed RTX 50 NR runtime path.

## Known limitation

Steam's built-in FPS counter disappears while a DLSS Super Resolution profile is active. It remains visible in **DLAA Native** and with project processing **OFF**. This affects the Steam overlay display, not DLSS or Neural Rendering itself.

## Checksums

`GTAIV-DLSS-Setup.sha256` contains the installer hash, and `SHA256SUMS.txt` covers the complete published payload set.

---

Thanks to **FusionFix, b-bridge, DXVK, ReShade, DLSS5-Feeder, and LumeniteFX** for the projects this integration builds on.
