# GTA IV — DLAA + DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering

A guided GTA IV integration for **NVIDIA DLAA (native-resolution anti-aliasing)**, **DLSS 4.5 Super Resolution**, and **DLSS 5 Neural Rendering**.

The supported install order is:

**FusionFix → DLAA → ReShade controls fix → DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering**

Neural Rendering is installed in the final step but stays **OFF by default** until you enable it in ReShade.

> **Tested hardware:** RTX 4070 Ti SUPER. DLSS Super Resolution has been tested in Custom Ultra Quality, Quality, Balanced, Performance and Ultra Performance. The current startup-stabilization system also fixes the low-resolution vibration that previously appeared on a cold launch.

## Quick install index

| Step | Install | What you run | What it does | You are finished when... |
|---|---|---|---|---|
| **[1](#step-1)** | **FusionFix** | FusionFix 5.0.1 installer/files | Gives GTA IV the modern renderer fixes this project builds on. | GTA IV launches normally with FusionFix installed. |
| **[2](#step-2)** | **DLAA baseline** | `Install-DLAA.bat` | Installs the bridge, ReShade, motion/depth helpers and NVIDIA DLSS runtime, then enables high-quality native-resolution anti-aliasing. | GTA IV launches and the DLSS log reports DLAA frames being delivered. |
| **[3](#step-3)** | **ReShade controls fix** | `BUILD.bat`, then `INSTALL.bat` | Makes the ReShade overlay usable even though GTA IV and the modern renderer run in different processes. | Pressing **Home** opens ReShade and the mouse/keyboard work inside it. |
| **[4](#step-4)** | **DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering** | `Install-DLSS-Full.bat` | Adds real DLSS resolution scaling, automatic startup stabilization, Neural Rendering, and the in-game **GTA IV DLSS** settings panel. | GTA IV starts stably and `Home → Add-ons → DLSS 5 Feed → GTA IV DLSS` lets you change quality and Neural Rendering. |

### What you get after all four steps

- DLAA at native resolution.
- DLSS 4.5 Super Resolution with five selectable quality modes.
- Automatic startup stabilization before low-resolution DLSS modes are used.
- DLSS 5 Neural Rendering already installed and ready to turn ON/OFF.
- **One normal settings surface inside ReShade** for DLSS quality and Neural Rendering.
- `DLSS-Full-Control.bat` only for launch, startup repair, status and diagnostics.

This repository contains the installers, integration code, configuration and validation. Third-party components are fetched from pinned upstream sources and verified where practical.

## What the project is doing

### DLAA

At the end of Step 2 the game still renders at your normal output resolution. NVIDIA DLAA then performs temporal anti-aliasing without lowering the game's render resolution.

```text
GTA IV
  -> FusionFix
  -> 64-bit bridge renderer
  -> ReShade + depth/motion data
  -> NVIDIA DLAA
  -> display
```

### DLSS 4.5 Super Resolution

Step 4 lets GTA IV render internally at a lower resolution and then reconstructs the image to your full output resolution with DLSS.

```text
GTA IV internal render resolution
  -> synchronized temporal information
  -> depth + motion data
  -> DLSS 4.5 Super Resolution
  -> display/output resolution
```

Available quality modes:

```text
Custom Ultra Quality (77% render scale)
Quality
Balanced
Performance
Ultra Performance
```

### Automatic startup stabilization

Very low DLSS render resolutions could previously start in a visibly vibrating state after a cold launch.

The current build solves that automatically:

```text
start briefly at 1485×835
  -> keep temporal data synchronized for 180 frames
  -> switch automatically to your saved DLSS quality mode
```

You do not need to perform this manually.

### DLSS 5 Neural Rendering

The final installer also installs the tested RTX 40/50-compatible Neural Rendering runtime:

```text
GTAIV\.trex\m3k\nvngx_dlssnr.dll
```

It is **installed but OFF by default**.

When you enable it, the rendering order is:

```text
GTA IV internal image
  -> DLSS 5 Neural Rendering
  -> DLSS 4.5 Super Resolution
  -> display/output resolution
```

The public default is **one Neural Rendering pass**. Higher pass counts remain available as an advanced/experimental ReShade control.

## Prerequisites

| Step | Requirement |
|---|---|
| Base game | GTA IV: Complete Edition / working PC installation containing `GTAIV.exe` |
| Step 1 | FusionFix 5.0.1 |
| Steps 2–4 | NVIDIA RTX GPU, suitable NVIDIA driver, internet access |
| Steps 3–4 | Git for Windows |
| Steps 3–4 | Python 3 in `PATH` |
| Steps 3–4 | Visual Studio 2022 Build Tools with **Desktop development with C++**, x86+x64 MSVC tools, and a Windows SDK |
| Steps 2–3 | Administrator permission for the ReShade Vulkan layer |
| Neural Rendering | Current automatic Neural Rendering runtime is the tested RTX 40/50-compatible build; direct project validation is on RTX 4070 Ti SUPER |

### Driver notes

`nvngx_dlss.dll` 310.9.1 reports a minimum NVIDIA driver of **512.15**.

The tested `nvngx_dlssnr.dll` 310.8.0-RTX40 runtime reports a minimum driver of **615.00**. If Neural Rendering stays OFF, only the DLAA/Super Resolution requirements apply. If you turn Neural Rendering ON, use **615.00 or newer**.

## No manual runtime downloads are required

The supported installer flow fetches or builds the required components itself, including:

```text
b-bridge
ReShade 6.8.0 Full Add-On Support
DLSS5-Feeder 0.15.1
LumeniteFX
nvngx_dlss.dll 310.9.1
nvngx_dlssnr.dll 310.8.0-RTX40
```

You do not need to find a separate Neural Rendering DLL or an old third-party Neural Rendering injector.

# Installation

<a id="step-1"></a>

## STEP 1 — Install FusionFix

**Purpose:** establish the clean GTA IV renderer baseline required by the rest of the project.

Install **FusionFix 5.0.1** into a clean GTA IV installation.

Launch GTA IV once and verify FusionFix works normally. Close the game completely afterward.

**Done when:** GTA IV launches normally with FusionFix and there is no previous `.trex`/bridge experiment in the game folder.

---

<a id="step-2"></a>

## STEP 2 — Install DLAA

**Purpose:** install the 64-bit rendering bridge, ReShade, motion/depth helpers and DLSS runtime, then establish the known-good native-resolution DLAA baseline.

Copy:

```text
install/Install-DLAA.bat
```

beside `GTAIV.exe` and run it.

The installer sets up the required bridge/ReShade stack and installs `nvngx_dlss.dll` 310.9.1.

Launch GTA IV once after Step 2.

**Done when:** the game launches normally and `.trex\dlss5-feed.log` shows DLAA frames being delivered.

Read [`docs/DLAA.md`](docs/DLAA.md) for details.

---

<a id="step-3"></a>

## STEP 3 — Install the ReShade controls fix

**Purpose:** make the ReShade overlay actually respond to Home, mouse and keyboard input.

GTA IV owns the game window while ReShade runs in the separate 64-bit renderer process. Stock ReShade therefore cannot normally capture the game's input. This patch reconnects the input correctly.

Open:

```text
tools/reshade-bbridge-input/
```

1. Double-click **`BUILD.bat`** and wait for `BUILD SUCCESS - PATCH MARKER VERIFIED`.
2. Close that window.
3. **Right-click `INSTALL.bat` → Run as administrator.**
4. Paste or drag the GTA IV folder containing `GTAIV.exe` into the installer.
5. Launch GTA IV.
6. Press **Home**.

**Done when:** ReShade opens and you can move the cursor, click controls and type inside the overlay.

If Home does nothing, stop here and troubleshoot before Step 4.

Read [`docs/RESHade-INPUT-PATCH.md`](docs/RESHade-INPUT-PATCH.md).

---

<a id="step-4"></a>

## STEP 4 — Install DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering

**Purpose:** add DLSS resolution scaling, automatic startup stabilization, the Neural Rendering runtime, and the in-game DLSS settings panel.

Copy:

```text
install/Install-DLSS-Full.bat
```

beside `GTAIV.exe` and run it.

The installer:

- adds the tested temporal synchronization required for stable DLSS reconstruction;
- adds Custom Ultra Quality / Quality / Balanced / Performance / Ultra Performance modes;
- adds the automatic `1485×835` startup stabilization;
- keeps `nvngx_dlss.dll` 310.9.1 as the DLSS 4.5 Super Resolution/DLAA runtime;
- downloads and verifies `nvngx_dlssnr.dll` 310.8.0-RTX40;
- installs the Neural Rendering runtime;
- adds **Neural Rendering ON/OFF** and **DLSS quality** controls to ReShade;
- defaults to **Quality**, **Neural Rendering OFF**, and **1 NR pass**;
- installs `DLSS-Full-Control.bat` only as a launch/repair/diagnostics helper.

**Done when:** GTA IV starts through the brief stabilization phase, switches cleanly to the saved quality mode, and the **GTA IV DLSS** ReShade panel is available.

Read [`docs/DLSS-FULL.md`](docs/DLSS-FULL.md).

### Configure DLSS in ReShade

Press **Home**, then open:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

That panel is the normal settings interface for this project.

It contains:

- **Neural Rendering** — OFF / ON. Changes are saved automatically.
- **Neural Rendering passes (advanced)** — defaults to **1**, which is the tested public configuration. Higher values are experimental and more expensive.
- **DLSS Super Resolution quality** — Custom Ultra Quality (77%), Quality, Balanced, Performance or Ultra Performance. Changes apply live and are saved automatically.

You do **not** need to close GTA IV or run a BAT file to change DLSS quality or Neural Rendering.

### DLSS tools helper

`DLSS-Full-Control.bat` is no longer a second settings menu. Use it only for:

```text
L  Launch GTA IV with startup stabilization pre-armed
R  Repair / re-arm startup stabilization settings
S  Show current DLSS / Neural Rendering status
D  Open the DLSS diagnostic log
```

The repair option preserves your saved DLSS quality, Neural Rendering state and NR pass count.

## DLSS model / preset selector

The upstream DLSS model/preset control is in the same ReShade add-on:

```text
Home -> Add-ons -> DLSS 5 Feed -> DLSS render preset -> Preset
```

Recommended starting point: **K**. J is the modern alternative if K leaves visible ghosting. E/F are older fallback models useful mainly for troubleshooting.

Changing the preset rebuilds the DLSS feature and may briefly hitch.

## Verification

Main runtime log:

```text
GTAIV\.trex\dlss5-feed.log
```

For ordinary users, the easiest checks are visual:

- DLAA: stable native-resolution image with improved anti-aliasing.
- DLSS Super Resolution: the game switches from the brief startup-stabilization resolution to your selected quality mode.
- Neural Rendering ON: the game continues through the same stable startup sequence and the log reports successful Neural Rendering initialization/evaluation.

The log contains internal engineering labels such as `M3K-A3-S5`, `M3K-SR-LIVE`, `M3K-A0` and `M3K-A1`. These are **debug labels**, not extra install stages.

See [`docs/VERIFY.md`](docs/VERIFY.md) if you need to interpret them.

## User-facing names vs internal debug names

You may encounter these names in old test notes, source code or logs:

| Internal/debug name | What it means for a user |
|---|---|
| `A3-S2` | **Temporal synchronization** — keeps GTA IV's per-frame rendering offsets and DLSS temporal sample aligned. |
| `A3-S5` | **Startup stabilization** — briefly starts at 1485×835 before switching to your saved DLSS quality mode. |
| `M3K` | **Project DLSS integration layer** — internal code/config namespace used by this project. |
| `Feature 18` / `NR18` | **DLSS 5 Neural Rendering** — NVIDIA's internal NGX feature identifier. |
| `true source` | **Internal render resolution** — the resolution GTA IV actually renders before DLSS reconstruction. |
| `presenter` | **Display/output resolution** — the final resolution sent to the window/monitor. |
| `SRProfile` | **Saved DLSS quality mode** — the config key storing Custom Ultra Quality/Quality/Balanced/Performance/Ultra Performance. |
| `UQ77` | **Custom Ultra Quality (77%)** — the project's high-resolution DLSS mode. |

These internal labels are retained only where they help with debugging or reproduce exact tested checkpoints.

## Known-good component versions

| Component | Current project baseline |
|---|---|
| FusionFix | 5.0.1 |
| ReShade | 6.8.0 Full Add-On Support + cross-process controls fix |
| DLSS5-Feeder | 0.15.1 upstream base + project integration changes |
| LumeniteFX | pinned project version |
| DLSS 4.5 Super Resolution / DLAA runtime | `nvngx_dlss.dll` 310.9.1 |
| DLSS 5 Neural Rendering runtime | `nvngx_dlssnr.dll` 310.8.0-RTX40 |
| DLSS settings | ReShade `Add-ons -> DLSS 5 Feed -> GTA IV DLSS` |
| Startup stabilization | 1485×835 for 180 synchronized frames, then saved DLSS mode |
| Neural Rendering default | OFF |
| Neural Rendering passes | 1 by default; higher counts advanced/experimental |

Exact source commits, package URLs and hashes are kept in [`manifests/versions.json`](manifests/versions.json) for reproducibility.

## Important limitations

- GTA IV is a 32-bit game while the modern DLSS/ReShade processing runs in a separate 64-bit renderer process.
- GTA IV does not provide modern engine-native motion vectors; LumeniteFX estimates the motion/depth data required by the temporal reconstruction.
- The combined module currently relies on the tested `1485×835` startup stabilization before switching to the saved DLSS mode.
- Locally compiled integration DLLs can differ byte-for-byte between Visual Studio/MSVC versions even when they are built from the exact same frozen source. Source/build/test validation is therefore more important than identical compiler output hashes.
- DLSS 5 Neural Rendering is substantially more expensive than Super Resolution alone on RTX 40 hardware.
- The automatic Neural Rendering runtime currently follows the tested RTX 40/50 path; other GPU-generation variants are outside this validated installer flow.
- The ReShade controls fix replaces the global Vulkan ReShade DLL under `C:\ProgramData\ReShade`. Restore the original before using software where a custom global graphics layer is inappropriate, especially anti-cheat titles.
- No ray tracing or path tracing is part of this project's DLSS 4.5 Super Resolution / DLSS 5 Neural Rendering implementation.

## Repository layout

```text
install/                         Current installers, ReShade-control build stage, and DLSS tools helper
config/                          Baseline configuration fragments
manifests/versions.json          Exact technical versions, source checkpoints and hashes
input/                           Developer-only local experiment area; normal install needs no files here
docs/                            User guides plus technical architecture/verification notes
tools/reshade-bbridge-input/     ReShade cross-process controls fix
tools/debug/                     Historical/debugging tools
```

## Credits & acknowledgements

- [FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) — ThirteenAG and contributors
- [b-bridge](https://github.com/gutbash/b-bridge) — gutbash and contributors
- [DXVK](https://github.com/doitsujin/dxvk) — doitsujin and contributors
- [ReShade](https://github.com/crosire/reshade) — Patrick Mours / crosire and contributors
- [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) — jlrouzies-fr and contributors
- [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX) — umar-afzaal and contributors
- [NVIDIA](https://developer.nvidia.com/rtx/dlss) — NGX / DLSS technology and runtimes
- [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo) — pinned DLSS Super Resolution and RTX40-compatible Neural Rendering runtime packages
- [DLSS5 Autopilot](https://github.com/Kizzuwatnaa/DLSS5-Autopilot) — compatibility research around DLSS 5 Neural Rendering GPU/runtime variants
- **Rockstar Games** — Grand Theft Auto IV

See [`docs/THIRD-PARTY.md`](docs/THIRD-PARTY.md).

Grand Theft Auto, Rockstar Games, NVIDIA, GeForce, RTX, DLSS and other product names are trademarks of their respective owners. This is an independent community project and is not affiliated with, endorsed by, or sponsored by Rockstar Games, NVIDIA, or the upstream projects listed above.
