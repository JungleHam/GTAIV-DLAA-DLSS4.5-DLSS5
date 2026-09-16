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
- `DLSS-Full-Control.bat` for quality selection, NR ON/OFF and recommended launching.

**Neural Rendering is installed but OFF by default.**

## Install

Copy:

```text
install/Install-DLSS-Full.bat
```

beside `GTAIV.exe` and run it.

Choose the DLSS Super Resolution quality mode you want to save. **Quality** is the default recommendation.

After installation, use:

```text
DLSS-Full-Control.bat
```

for normal control and launching.

## DLSS quality modes

| Choice | User-facing mode | Meaning |
|---:|---|---|
| 1 | Custom Ultra Quality (77%) | Highest internal render resolution of the upscaling modes. |
| 2 | Quality | Recommended general-purpose default. |
| 3 | Balanced | Middle ground between image quality and performance. |
| 4 | Performance | Lower internal render resolution for more GPU headroom. |
| 5 | Ultra Performance | Lowest internal render resolution; mainly useful when maximum performance is needed. |

The config file stores this as `SRProfile`, but users normally change it through `DLSS-Full-Control.bat` instead of editing the file manually.

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

## Neural Rendering

Step 4 automatically downloads and verifies:

```text
nvngx_dlssnr.dll 310.8.0-RTX40
```

and installs it to:

```text
GTAIV\.trex\m3k\nvngx_dlssnr.dll
```

After installation, NR is present but disabled.

### Turn Neural Rendering ON

Close GTA IV and run:

```text
DLSS-Full-Control.bat
```

Choose:

```text
N  Turn NR ON
```

Then launch with `L`.

When enabled, the rendering order is:

```text
GTA IV internal image
 -> DLSS 5 Neural Rendering
 -> DLSS 4.5 Super Resolution
 -> display/output resolution
```

The tested configuration uses **one Neural Rendering pass**.

### Turn Neural Rendering OFF

Close GTA IV, run the control helper and choose:

```text
O  Turn NR OFF
```

DLSS Super Resolution remains enabled.

## Requirements

Complete Steps 1–3 first.

For the reproducible local build used by this installer you also need:

- Git for Windows;
- Python 3 in `PATH`;
- Visual Studio 2022 Build Tools;
- Desktop development with C++ / x86+x64 MSVC tools;
- Windows SDK;
- internet access.

The tested Neural Rendering runtime requires NVIDIA driver **615.00 or newer** when NR is enabled. Direct project hardware validation is on RTX 4070 Ti SUPER.

## Verification

The main runtime log is:

```text
GTAIV\.trex\dlss5-feed.log
```

For an ordinary user, the important result is simple:

1. launch through `DLSS-Full-Control.bat` → `L`;
2. the game briefly initializes at the stabilization resolution;
3. it switches automatically to the saved DLSS mode;
4. the image remains stable instead of vibrating.

If you need log-level proof, see [`VERIFY.md`](VERIFY.md).

## Technical identities

For exact reproduction and debugging, the current validated implementation corresponds to these internal checkpoints:

```text
Temporal synchronization: A3-S2
Startup stabilization:    A3-S5
Project checkpoint:       57a8bd2ede8d7b4b721b1981bc0e8a7e6cbe084f
```

Those codes are intentionally kept out of the normal installation instructions because they describe engineering checkpoints, not user-selectable features.

Hardware-reference hashes and pinned source revisions are recorded in `manifests/versions.json`.

## Rollback

The installer creates:

```text
_DLSS_FULL_PREINSTALL_BACKUP_<timestamp>
```

beside `GTAIV.exe` and records its location in `DLSS_FULL_INSTALLED.txt`.

Close GTA IV and `NvRemixBridge.exe` before restoring files from that backup.
