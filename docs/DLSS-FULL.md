# DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering

This is **Step 4** of the normal installation.

Before it, complete:

```text
1. FusionFix
2. DLAA
3. ReShade controls fix
4. DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering  <- this guide
```

## What Step 4 adds

The combined installer gives you:

- real DLSS Super Resolution from a lower GTA IV internal render resolution to your full output resolution;
- Custom Ultra Quality, Quality, Balanced, Performance and Ultra Performance modes;
- the tested temporal synchronization required for stable DLSS reconstruction;
- automatic startup stabilization to prevent the cold-start vibration seen at low render resolutions;
- the tested DLSS 5 Neural Rendering runtime;
- a **GTA IV DLSS** panel inside ReShade for normal settings;
- `DLSS-Full-Control.bat` for launch, repair, status and diagnostics only.

**Neural Rendering is installed but OFF by default.**

## Install

Copy:

```text
install/Install-DLSS-Full.bat
```

beside `GTAIV.exe` and run it.

The public defaults are:

```text
DLSS quality:       Quality
Neural Rendering:  OFF
NR passes:          1
```

The installer does not ask you to choose quality because normal configuration is now done live inside ReShade.

## Configure DLSS in ReShade

Press **Home**, then open:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

This is the project's single normal settings surface.

### Neural Rendering

Use the **Neural Rendering** checkbox to turn DLSS 5 Neural Rendering OFF or ON.

The setting is saved automatically and the runtime switch is applied through the normal safe frame/config path rather than directly inside the UI callback.

### Neural Rendering passes

The same panel contains:

```text
Neural Rendering passes (advanced)
```

The tested public default is **1 pass**.

Higher pass counts remain available for experimentation, but they may hitch while warming and can cost significant performance.

### DLSS Super Resolution quality

The panel exposes only the five normal DLSS quality choices:

| Mode | Meaning |
|---|---|
| Custom Ultra Quality (77%) | Highest internal render resolution of the upscaling modes. |
| Quality | Recommended general-purpose default. |
| Balanced | Middle ground between image quality and performance. |
| Performance | Lower internal render resolution for more GPU headroom. |
| Ultra Performance | Lowest internal render resolution; mainly useful when maximum performance is needed. |

Quality changes apply live and are saved automatically.

The older internal DLAA-only reconstruction baseline is no longer shown in this public dropdown; it remains an engineering/debug path only.

## DLSS tools helper

`DLSS-Full-Control.bat` is no longer a settings menu.

It provides:

```text
L  Launch GTA IV with startup stabilization pre-armed
R  Repair / re-arm startup stabilization settings
S  Show current DLSS / Neural Rendering status
D  Open the DLSS diagnostic log
```

The repair action intentionally preserves:

- saved DLSS quality;
- Neural Rendering OFF/ON state;
- Neural Rendering pass count.

## Automatic startup stabilization

During testing, very low DLSS render resolutions could sometimes begin a fresh game session with visible vibration.

The reliable fix was to start briefly at a known-good internal resolution before moving to the requested DLSS mode:

```text
start at 1485×835
 -> wait for 180 frames with temporal data synchronized
 -> automatically switch to your saved DLSS quality mode
```

Known test points:

```text
1472×828  -> vibration remained
1478×832  -> fixed
1485×835  -> fixed
1493×840  -> vibration remained
```

The installer uses `1485×835` automatically. You do not need to change resolutions yourself.

## Temporal synchronization

DLSS uses tiny per-frame image offsets together with previous-frame information. GTA IV was never designed to provide this information to modern DLSS.

The project therefore applies one synchronized temporal sample to both GTA IV's rendered geometry and DLSS itself. This is what eliminated the large wobble/shimmer seen in earlier experimental builds.

Normal users do not need to configure this system.

Internal/source name: `A3-S2`.

## Startup stabilization

The automatic `1485×835` startup sequence described above is the project's cold-start fix.

Internal/source name: `A3-S5`.

These names may appear in logs or source code, but **they are not extra installation steps**.

## Neural Rendering runtime

Step 4 automatically downloads and verifies:

```text
nvngx_dlssnr.dll 310.8.0-RTX40
```

and installs it to:

```text
GTAIV\.trex\m3k\nvngx_dlssnr.dll
```

When Neural Rendering is enabled in the ReShade panel, the rendering order is:

```text
GTA IV internal image
 -> DLSS 5 Neural Rendering
 -> DLSS 4.5 Super Resolution
 -> display/output resolution
```

## Requirements

Complete Steps 1–3 first.

For the reproducible local build used by this installer you also need:

- Git for Windows;
- Python 3 in `PATH`;
- Visual Studio 2022 Build Tools;
- Desktop development with C++ / x86+x64 MSVC tools;
- Windows SDK;
- internet access.

The tested Neural Rendering runtime requires NVIDIA driver **615.00 or newer** when Neural Rendering is enabled. Direct project hardware validation is on RTX 4070 Ti SUPER.

## Verification

The main runtime log is:

```text
GTAIV\.trex\dlss5-feed.log
```

For an ordinary user, the important result is simple:

1. launch the game, preferably through `DLSS-Full-Control.bat` → `L` so startup stabilization is pre-armed;
2. the game briefly initializes at the stabilization resolution;
3. it switches automatically to the saved DLSS mode;
4. press Home and verify `Add-ons -> DLSS 5 Feed -> GTA IV DLSS` is available;
5. quality and Neural Rendering changes can then be made live from that panel.

If you need log-level proof, see [`VERIFY.md`](VERIFY.md).

## Technical identities

For exact reproduction and debugging, the rendering core corresponds to these internal checkpoints:

```text
Temporal synchronization: A3-S2
Startup stabilization:    A3-S5
Frozen core checkpoint:   57a8bd2ede8d7b4b721b1981bc0e8a7e6cbe084f
```

The public build then applies a small post-checkpoint ReShade-controls source stage. It changes the settings UI/INI control path only; the frozen temporal and startup rendering logic is not modified.

Those codes are intentionally kept out of the normal installation instructions because they describe engineering checkpoints, not user-selectable features.

Hardware-reference hashes and pinned source revisions are recorded in `manifests/versions.json`.

## Rollback

The installer creates:

```text
_DLSS_FULL_PREINSTALL_BACKUP_<timestamp>
```

beside `GTAIV.exe` and records its location in `DLSS_FULL_INSTALLED.txt`.

Close GTA IV and `NvRemixBridge.exe` before restoring files from that backup.
