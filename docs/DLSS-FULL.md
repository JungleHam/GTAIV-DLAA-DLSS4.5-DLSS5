# DLSS Full

Use the release-facing installer:

```text
install/Install-DLSS-Full.bat
```

**Right-click → Run as administrator**, enter the folder containing `GTAIV.exe`, then confirm.

It installs the frozen/tested DLSS integration, startup stabilization, in-game ReShade controls, and a GPU-appropriate Neural Rendering runtime.

## Neural Rendering runtime

| GPU | Runtime |
|---|---|
| RTX 50 | Original NVIDIA-signed `nvngx_dlssnr.dll` 310.8.0. |
| RTX 40 | Project-tested RTX 40 compatibility `nvngx_dlssnr.dll` 310.8.0. |

The installer detects RTX 40/50 automatically. For an unrecognized GPU it asks which runtime to use rather than guessing.

Defaults:

```text
DLSS: Quality
Neural Rendering: OFF
NR passes: 1
```

## In-game controls

Press **Home**:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

Available controls:

- master DLSS / DLAA processing ON/OFF;
- DLAA Native, Custom Ultra Quality 77%, Quality, Balanced, Performance, Ultra Performance;
- Neural Rendering ON/OFF;
- Neural Rendering pass count;
- compact resolution/status diagnostics.

Master OFF safely transitions to native rendering before disabling DLSS/DLAA/NR/jitter. OFF is session-only so the next launch can still use the 1485×835 startup stabilization.

## Startup stabilization

Cold starts briefly use:

```text
1485×835 -> 180 synchronized frames -> saved DLSS/DLAA mode
```

Keep GTA IV's own display resolution set to the monitor's native resolution. Internal DLSS scaling is handled separately.

## Logs

```text
GTAIV\.trex\dlss5-feed.log
```

For deeper verification see [VERIFY.md](VERIFY.md).
