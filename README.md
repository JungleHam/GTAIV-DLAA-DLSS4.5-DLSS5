# GTA IV Scaling

GTA IV Scaling is a unified reconstruction and anti-aliasing layer for **GTA IV: Complete Edition** on Windows.

It adds live switching between **native rendering**, **NVIDIA DLAA / DLSS**, and **AMD FidelityFX FSR** from one runtime and one installer.

## Installation

### What you need

- **GTA IV: Complete Edition**
- **Windows 10/11 64-bit**
- Administrator access for the ReShade/Vulkan setup
- The official **ReShade 6.8.0 Full Add-On Support** installer when setting up from a clean game

Everything else required by the project is handled by the installer.

### Clean installation

1. Download **`GTAIV-Scaling-Setup-v1.2.0.exe`** from the [Releases](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/releases) page.
2. Run it as **Administrator**.
3. Select the folder containing **`GTAIV.exe`**.
4. Choose **Install / Repair GTA IV Scaling 1.2.0**.
5. If FusionFix is missing, the installer downloads and installs pinned **FusionFix 5.0.1**.
6. Launch GTA IV once to the main menu, close the game, and run the installer again so FusionFix can create its first-run state.
7. If the scaling foundation is not already installed, select the official **ReShade 6.8.0 Full Add-On Support** setup EXE when asked.
8. Finish installation and launch GTA IV.

There is **no DLSS-vs-FSR installer choice**. The full shared runtime is installed once and the game only shows the scaling technologies supported by the detected GPU.

### Repair / upgrade

Run the same installer again and choose **Install / Repair**.

The installer backs up the project-owned scaling files before replacing the stack.

### Removal

Run the same installer and choose **Remove GTA IV Scaling**.

The project uninstaller removes the scaling integration while preserving external components where possible.

### Open the in-game controls

```text
Home -> Add-ons -> GTA IV Scaling 1.2.0
```

## Functions

- **Off - Native** — true reconstruction-off / native rendering path.
- **NVIDIA DLAA** — native-resolution temporal anti-aliasing.
- **NVIDIA DLSS Super Resolution** — lower internal render resolution reconstructed to output resolution.
- **AMD FidelityFX FSR 3.1.4 Vulkan** — independent non-NGX reconstruction backend.
- **Live backend switching** — switch between Off, NVIDIA and AMD without restarting the game.
- **Safe NVIDIA <-> AMD handoff** — vendor switches pass through an explicit native/raw midpoint.
- **No silent vendor fallback** — a failed NVIDIA or AMD open does not silently substitute the other backend.
- **RTX capability filtering** — NVIDIA scaling is hidden on non-RTX systems.
- **RTX 20/30 support** — DLAA/DLSS + FSR, without DLSS Neural Rendering.
- **RTX 40/50 support** — DLAA/DLSS + FSR + optional DLSS Neural Rendering.
- **Automatic NR package selection** — matched RTX 40/50 NR runtime is installed automatically and starts OFF.
- **DLAA Native preset** — 100% render scale.
- **DLSS Custom Ultra Quality preset** — 77% render scale.
- **DLSS Quality preset** — 67% render scale.
- **DLSS Balanced preset** — 58% render scale.
- **DLSS Performance preset** — 50% render scale.
- **DLSS Ultra Performance preset** — 33% render scale.
- **DLSS custom render scale** — 10–100%.
- **Staged DLSS scale Apply button** — moving the slider does not constantly resize the game.
- **NVIDIA sharpening** — independent 0.00–1.50 post-DLSS sharpening.
- **NVIDIA jitter sequence control** — Auto / 8 / 16 / 32 phases.
- **NVIDIA jitter compensation control** — +X/+Y, -X/-Y, +X/-Y, -X/+Y.
- **Calibrated NVIDIA defaults** — 8 phases + -X/-Y.
- **FSR Native AA preset** — 100% render scale.
- **FSR Ultra Quality preset** — 77% render scale.
- **FSR Quality preset** — 66.7% render scale.
- **FSR Balanced preset** — 59% render scale.
- **FSR Performance preset** — 50% render scale.
- **FSR Ultra Performance preset** — 33% render scale.
- **FSR custom render scale** — 10–100%.
- **AMD RCAS sharpening** — independent 0.00–1.00 control.
- **Independent AMD phase planning** — FSR manages its own temporal phase count.
- **Exact GTA IV raster-jitter handoff** — temporal offsets are passed into reconstruction.
- **Fixed/default FSR exposure** — removes the earlier brightness/vignette pulse.
- **Calibrated FSR camera/depth contract** — GTA IV near/far/FOV/depth configuration is supplied to FSR.
- **Independent NVIDIA and AMD settings** — switching backends does not overwrite the other backend's scale or sharpening.
- **DLSS Neural Rendering toggle** — installed on supported RTX 40/50 systems and OFF by default.
- **NR styles** — Default / Natural / Cinematic.
- **NR Intensity** — 0.00–2.00.
- **NR Local Tone** — 0.00–2.00.
- **NR Local Structure** — 0.00–2.00.
- **NR Skin Structure** — 0.00–2.00.
- **NR Auto Mask** — on/off.
- **NR UI Correction** — on/off.
- **NR passes** — 1–5 passes.
- **Reset NR Advanced** — restores the project NR defaults.
- **Diagnostics panel** — requested/active backend, transition state, render sizes, jitter, FSR and NR state.
- **Persistent settings** — saved backend-specific choices survive normal restarts.
- **Unified Install / Repair** — one installer handles the complete scaling stack.
- **Automatic FusionFix install** — pinned FusionFix 5.0.1 is installed when missing.
- **Automatic project dependency handling** — bridge/presenter, LumeniteFX, runtime files and input patch are handled by setup.
- **Project-file backup before repair/upgrade** — existing scaling files are preserved before replacement.
- **Integrated removal** — the same installer can remove GTA IV Scaling.
- **ReShade input relay patch** — keeps keyboard/mouse control of the overlay across the 32-bit/64-bit bridge.

## Current release

**v1.2.0**

Installer: **`GTAIV-Scaling-Setup-v1.2.0.exe`**

## Screenshots

[Screenshots](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/tree/main/screenshots)

## GPU support

| GPU | Off / Native | AMD FidelityFX FSR | NVIDIA DLAA / DLSS | DLSS Neural Rendering |
| --- | --- | --- | --- | --- |
| RTX 20 Series | Yes | Yes | Yes | No |
| RTX 30 Series | Yes | Yes | Yes | No |
| RTX 40 Series | Yes | Yes | Yes | Yes, installed OFF by default |
| RTX 50 Series | Yes | Yes | Yes | Yes, installed OFF by default |
| GTX / AMD / Intel / other non-RTX | Yes | Yes | Hidden | No |

The installer detects NVIDIA RTX capability and writes it into the runtime configuration.

On non-RTX systems the NVIDIA choice is hidden, and an old saved NVIDIA selection is automatically moved to AMD FSR instead of trying to open an unavailable backend.

NR is deliberately restricted to the tested RTX 40/50 paths. RTX 20/30 still get the normal NVIDIA DLAA/DLSS path plus FSR.

## Installation

### What you need

- **GTA IV: Complete Edition**
- **Windows 10/11 64-bit**
- Administrator access for the ReShade/Vulkan setup
- The official **ReShade 6.8.0 Full Add-On Support** installer when setting up from a clean game

Everything else required by the project is handled by the installer.

### Clean installation

1. Download **`GTAIV-Scaling-Setup-v1.2.0.exe`** from the [Releases](https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5-FSR/releases) page.
2. Run it as **Administrator**.
3. Select the folder containing **`GTAIV.exe`**.
4. Choose **Install / Repair GTA IV Scaling 1.2.0**.
5. If FusionFix is missing, the installer downloads and installs pinned **FusionFix 5.0.1**.
6. Launch GTA IV once to the main menu, close the game, and run the installer again so FusionFix can create its first-run state.
7. If the scaling foundation is not already installed, select the official **ReShade 6.8.0 Full Add-On Support** setup EXE when asked.
8. Finish installation and launch GTA IV.

There is **no DLSS-vs-FSR installer choice**. The full shared runtime is installed once; the game decides which scaling technologies to show from the detected GPU capability.

### Repair / upgrade

Run the same installer again and choose **Install / Repair**.

The installer backs up the project-owned scaling files before replacing the stack.

### Removal

Run the same installer and choose **Remove GTA IV Scaling**.

The project uninstaller removes the scaling integration while preserving external components where possible.

## In-game controls

Open:

```text
Home -> Add-ons -> GTA IV Scaling 1.2.0
```

The main panel is **GTA IV Scaling**.

### Scaling Technology

On RTX:

```text
Off - Native
NVIDIA DLAA / DLSS
AMD FidelityFX FSR
```

On non-RTX:

```text
Off - Native
AMD FidelityFX FSR
```

Backend switches are live.

NVIDIA <-> AMD switches are serialized through a native/raw midpoint so one vendor backend is not destroyed while another still owns GPU resources. There is no silent cross-vendor fallback.

**Off - Native** is a true reconstruction-off path: no DLAA, DLSS, FSR, or Neural Rendering evaluation after the native transition completes.

NVIDIA and AMD settings are stored independently so changing one backend does not overwrite the other backend's scale or sharpening choices.

## NVIDIA DLAA / DLSS

The NVIDIA path uses the project's pinned DLSS runtime and supports both DLAA and Super Resolution.

### Presets

- **DLAA Native — 100%**
- **Custom Ultra Quality — 77%**
- **Quality — 67%**
- **Balanced — 58%**
- **Performance — 50%**
- **Ultra Performance — 33%**
- **Custom Render Scale — 10% to 100%**

The custom scale slider is staged: moving it only changes the preview value. **Apply** performs the resolution change, avoiding constant resize churn while dragging the slider.

100% custom scale resolves to DLAA/native reconstruction.

If NVIDIA rejects feature creation at an unusual forced scale, the runtime reports it and keeps the previous valid reconstruction instead of silently switching vendor backends.

### NVIDIA sharpening

Independent post-DLSS sharpening:

- range: **0.00 to 1.50**
- 0.00 = off
- 0.35 = mild
- 0.75 = strong
- 1.50 = extreme

This is separate from AMD RCAS.

### Temporal AA / jitter controls

Advanced controls include:

- **Auto**
- **8 phases**
- **16 phases**
- **32 phases**

NVIDIA also exposes live jitter-compensation sign calibration:

- +X / +Y
- -X / -Y
- +X / -Y
- -X / +Y

The hardware-tested v1.2.0 default is:

```text
Jitter sequence: 8 phases
NVIDIA jitter compensation: -X / -Y
```

That calibration preserved the strong AA benefit while removing the excessive shimmer seen with the earlier sign convention. DLAA was clean in hardware testing; aggressive lower render scales can still show the mild temporal wobble expected from lower-resolution temporal reconstruction.

## AMD FidelityFX FSR

v1.2.0 adds an independent **FidelityFX FSR 3.1.4 Vulkan** reconstruction backend.

It does not use NGX as a hidden fallback.

### FSR presets

- **Native AA — 100%**
- **Ultra Quality — 77%**
- **Quality — 66.7%**
- **Balanced — 59%**
- **Performance — 50%**
- **Ultra Performance — 33%**
- **Custom Render Scale — 10% to 100%**

FSR has its own custom scale and render planner, independent of the NVIDIA profile/scale state.

### AMD RCAS sharpening

Independent FidelityFX RCAS control:

- range: **0.00 to 1.00**
- 0.00 = off
- 0.25 = mild
- 0.50 = medium
- 1.00 = maximum

### FSR temporal behavior

The AMD path uses GTA IV's exact raster jitter handoff with FidelityFX's own independent phase planning.

v1.2.0 also switches FSR to fixed/default exposure instead of the earlier internal auto-exposure path. This removed the brightness/vignette-like pulsing seen during hardware testing.

The calibrated GTA IV camera/depth contract used by FSR is:

- near plane: 0.05
- far plane: 1500
- vertical FOV: 45 degrees
- finite, non-reversed depth

## DLSS Neural Rendering

Neural Rendering is optional and starts **OFF**.

The installer only installs the NR runtime on the tested generations:

- **RTX 40 Series:** tested compatibility runtime
- **RTX 50 Series:** NVIDIA-signed runtime

RTX 20/30 use DLAA/DLSS without NR.

If you already have the exact supported `nvngx_dlssnr.dll`, the installer can use a local copy instead; it is still hash-checked.

### NR controls

Advanced NR controls include:

- style:
  - Default
  - Natural
  - Cinematic
- Intensity: **0.00–2.00**
- Local Tone: **0.00–2.00**
- Local Structure: **0.00–2.00**
- Skin Structure: **0.00–2.00**
- Auto Mask
- UI Correction
- **1–5 Neural Rendering passes**
- Reset NR Advanced

The reset defaults are:

```text
Style: Default
Intensity: 1.00
Local Tone: 1.00
Local Structure: 1.00
Skin Structure: 1.00
Auto Mask: ON
UI Correction: OFF
```

## Diagnostics and state

The Advanced/Diagnostics UI exposes useful runtime state including requested/active backend, backend transition state, requested/source/output resolution, saved custom scale, temporal jitter state, NVIDIA compensation, FSR state and NR tuning.

The runtime preserves per-backend configuration across live switches and normal restarts.

## Installer behavior

The v1.2.0 installer is a single unified **Install / Repair** flow.

It automatically handles or verifies the project-owned dependencies, including:

- FusionFix 5.0.1
- the pinned GTA IV bridge/presenter runtime
- LumeniteFX
- the project ReShade input patch
- the project NVIDIA DLAA/DLSS runtime
- the AMD FidelityFX FSR 3.1.4 backend
- GPU-matched NR on RTX 40/50

The normal manual prerequisite is the official **ReShade 6.8.0 Full Add-On Support** installer on a fresh setup.

The installer also records the detected GPU and installed feature capability in `GTAIV_SCALING_INSTALLED.txt`.

## Why the bridge exists

GTA IV is a **32-bit Direct3D 9** game, while the modern reconstruction stack is 64-bit.

The project bridges the game into a 64-bit Vulkan/ReShade environment:

```text
GTAIV.exe (32-bit D3D9)
        |
        v
FusionFix
        |
        v
b-bridge client
        |
        v
NvRemixBridge.exe (64-bit)
        |
        v
custom DXVK / Vulkan presenter
        |
        v
ReShade + LumeniteFX
        |
        +--> Off / Native
        |
        +--> NVIDIA DLAA / DLSS
        |       |
        |       +--> optional DLSS Neural Rendering
        |
        +--> AMD FidelityFX FSR 3.1.4
        |
        v
display
```

The bridge also carries GTA IV's temporal raster jitter and the input data required by reconstruction.

## ReShade input patch

GTA IV owns the game window while ReShade runs in the separate 64-bit bridge process.

The project includes a ReShade 6.8.0 input patch that relays keyboard and mouse input across that process boundary so the ReShade overlay remains usable.

## v1.2.0 release hashes

```text
Installer:
882FB425D9ABE8CFEA25583049B00A252AE730E4480EB3C78867691FEA446F85

Runtime ZIP:
7AE9FC16FF6AF6A49EF605B18B2606A8986F1E962E3A519C4DB6A5053834969B

v1.2 feeder:
AF35011DC5914DF2DB6B1C49B2EDDE751831F4F8AF53B80A26D7C079CA26BDFF

ReShade b-bridge input patch:
D5BD8CB2B6E935506888EA71711361B9AFCD72ED7C70926C0F52E8F8E47C7510
```

More pinned component details are in [`manifests/versions.json`](manifests/versions.json).

## Useful docs

- [Prerequisites and pinned packages](docs/PREREQUISITES.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Third-party components / redistribution policy](docs/THIRD-PARTY.md)
- [ReShade input patch](docs/RESHade-INPUT-PATCH.md)
- [FSR architecture and hardware checkpoints](docs/FSR_ARCHITECTURE.md)

## Credits

- [FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix)
- [b-bridge](https://github.com/gutbash/b-bridge)
- [DXVK](https://github.com/doitsujin/dxvk)
- [ReShade](https://github.com/crosire/reshade)
- [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder)
- [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX)
- [NVIDIA DLSS](https://github.com/NVIDIA/DLSS)
- [AMD FidelityFX SDK](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK)
- [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo)

This is an independent community integration project and is not affiliated with Rockstar Games, NVIDIA, AMD, or the upstream projects above.
