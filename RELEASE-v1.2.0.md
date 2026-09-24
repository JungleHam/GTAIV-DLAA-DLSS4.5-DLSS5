# v1.2.0 — GTA IV Scaling

v1.2.0 is the largest update since the original DLAA/DLSS release.

The project is now **GTA IV Scaling**: one installer and one live runtime for native rendering, NVIDIA DLAA/DLSS and AMD FidelityFX FSR.

## Highlights

- **AMD FidelityFX FSR 3.1.4 Vulkan** is now a full first-class backend.
- New live **Scaling Technology** selector:
  - Off - Native
  - NVIDIA DLAA / DLSS
  - AMD FidelityFX FSR
- **Live NVIDIA <-> AMD switching** is hardware-tested and serialized through a native/raw midpoint.
- New unified **GTA IV Scaling 1.2.0** installer.
- GPU-aware UI:
  - RTX: Off / NVIDIA / AMD
  - non-RTX: Off / AMD, NVIDIA hidden
- RTX 20/30 receive DLAA/DLSS + FSR without Neural Rendering.
- RTX 40/50 additionally receive the matched NR runtime, installed **OFF by default**.
- NVIDIA temporal calibration is now **8 phases + -X/-Y** by default.
- FSR exposure is fixed/default, eliminating the brightness/vignette pulse seen in earlier hardware tests.
- NVIDIA and AMD keep separate scaling and sharpening settings.

## NVIDIA DLAA / DLSS

Available modes:

- DLAA Native — 100%
- Custom Ultra Quality — 77%
- Quality — 67%
- Balanced — 58%
- Performance — 50%
- Ultra Performance — 33%
- Custom Render Scale — 10–100%

Custom scaling now uses an **Apply** button so dragging the scale slider does not constantly rebuild the render path.

Independent NVIDIA sharpening remains available from **0.00 to 1.50**.

### Temporal AA calibration

Hardware testing showed that disabling raster jitter removed shimmer but also damaged the AA result, so v1.2.0 keeps full temporal sampling.

The final calibrated default is:

```text
Jitter sequence: 8 phases
NVIDIA jitter compensation: -X / -Y
```

Advanced users can still select Auto / 8 / 16 / 32 phases and all four X/Y compensation combinations.

DLAA was clean in hardware testing. Lower DLSS scales can still show mild temporal wobble from aggressive low-resolution reconstruction.

## AMD FidelityFX FSR

The new AMD backend is independent from NVIDIA/NGX and uses **FidelityFX FSR 3.1.4 Vulkan**.

Available modes:

- Native AA — 100%
- Ultra Quality — 77%
- Quality — 66.7%
- Balanced — 59%
- Performance — 50%
- Ultra Performance — 33%
- Custom Render Scale — 10–100%

AMD also gets its own **RCAS sharpening** control from 0.00 to 1.00.

Other FSR work completed for this release:

- native Vulkan FSR session without NGX bootstrap
- independent FSR render planner
- exact GTA IV raster-jitter handoff
- independent FidelityFX phase planning
- calibrated GTA IV camera/depth contract
- fixed/default exposure instead of auto exposure
- clean Off <-> AMD live switching
- clean NVIDIA <-> AMD vendor switching
- no silent NGX fallback

The earlier subtle brightness/vignette pulsing was traced to FSR auto exposure and is fixed in v1.2.0.

## Off - Native

Off is now a real native/raw state.

After the transition completes:

- no DLAA evaluation
- no DLSS evaluation
- no FSR evaluation
- no Neural Rendering evaluation

Switching back into NVIDIA or AMD restores that backend's saved state.

## DLSS Neural Rendering

NR still starts **OFF**.

Installer support:

- RTX 40 Series: tested compatibility NR runtime
- RTX 50 Series: NVIDIA-signed NR runtime
- RTX 20/30: no NR runtime installed

Advanced NR controls include:

- Default / Natural / Cinematic styles
- Intensity
- Local Tone
- Local Structure
- Skin Structure
- Auto Mask
- UI Correction
- 1–5 passes
- Reset to project defaults

## New unified installer

The installer no longer asks users to choose between a DLAA package and a Full-DLSS package.

There is one **Install / Repair GTA IV Scaling 1.2.0** path.

It:

- detects the GTA IV folder
- installs pinned FusionFix 5.0.1 when missing
- asks for the official ReShade 6.8.0 Full Add-On Support setup only when needed
- installs the complete shared scaling runtime
- detects RTX capability
- installs matched NR only on RTX 40/50
- writes runtime GPU capability so unsupported NVIDIA options are hidden in-game
- backs up project-owned scaling files before replacing the stack
- supports repair and removal from the same EXE

## Backend switching and safety

v1.2.0 includes the full P9 live-switch work:

- AMD -> Off
- Off -> AMD
- NVIDIA -> Off
- Off -> NVIDIA
- NVIDIA -> AMD
- AMD -> NVIDIA

Vendor-to-vendor switches pass through an explicit native/raw midpoint.

The runtime waits for the target backend to actually become ready before committing the switch, and it does not silently substitute the other vendor backend on failure.

## Hardware validation

The primary hardware-validation system was:

- Ryzen 7 7700
- RTX 4070 Ti SUPER 16 GB
- 64 GB RAM
- Windows 11
- 2560x1440 output

The final v1.2.0 installer was also tested from a clean GTA IV state and the install, NVIDIA path, FSR path, live switching and restart persistence all passed.

## Release assets and hashes

### GTAIV-Scaling-Setup-v1.2.0.exe

```text
SHA256
882FB425D9ABE8CFEA25583049B00A252AE730E4480EB3C78867691FEA446F85
```

### GTAIV-Scaling-Runtime-v1.2.0.zip

```text
SHA256
7AE9FC16FF6AF6A49EF605B18B2606A8986F1E962E3A519C4DB6A5053834969B
```

### v1.2 feeder

```text
SHA256
AF35011DC5914DF2DB6B1C49B2EDDE751831F4F8AF53B80A26D7C079CA26BDFF
```

### ReShade b-bridge input patch

```text
SHA256
D5BD8CB2B6E935506888EA71711361B9AFCD72ED7C70926C0F52E8F8E47C7510
```

## Upgrade notes

v1.2.0 replaces the old public product naming with **GTA IV Scaling**, but internal `dlss5-feed` filenames and plumbing are intentionally retained for compatibility.

Existing installs can simply run **Install / Repair**. A clean reinstall is not required.

## Credits

Thanks to the upstream projects this integration builds on: FusionFix, b-bridge, DXVK, ReShade, DLSS5-Feeder, LumeniteFX, NVIDIA DLSS, AMD FidelityFX SDK and RankFTW/rhi-repo.
