# DLSS 5 Neural Rendering / Deep Fried Chicken

This is an **upgrade to the working DLAA installation**, not a replacement installer.

## Required base

Complete `Install-DLAA.bat` first and verify that genuine NGX DLAA is active.

The upgrade script checks for:

```text
.trex\NvRemixBridge.exe
.trex\ReShade.ini
.trex\dlss5-feed.addon64
.trex\dlss5-feed.cfg
.trex\nvngx_dlss.dll
```

It also verifies that the installed `nvngx_dlss.dll` is the tested 310.9.1 runtime.

## User-supplied files

See `../input/README.md`.

The tested files are identified by SHA256, not filename:

```text
Deep Fried Chicken 1.7.4 checkpoint 70 archive:
91dc4137b1f2d7cdbd7f9eb4de9d33848b59e3af7a747d5d798271ee262eab09

nvngx_dlssnr.dll 310.8.0:
4b8d19bc3eff58a084f5eca7489c921501c203450169fb82ff4f649a4482ba05
```

## Install

Copy `install/Upgrade-DLSS5-DFC.bat` beside `GTAIV.exe` and run it.

The script:

- searches beside the BAT, Desktop and Downloads for the exact tested files;
- creates `.trex\_PRE_DFC_BACKUP_<timestamp>`;
- extracts DFC using password `chicken`;
- removes known conflicting neural-provider add-ons;
- installs DFC and `nvngx_dlssnr.dll`;
- adds DFC to ReShade's `LoadFromDllMain` early-load list;
- sets the safe known-good initial DFC state;
- leaves Feeder in the proven native DLAA configuration.

## Known-good first-run state

```ini
arm=1
enabled=1
safe_neutral_start=0
```

Feeder remains:

```ini
enabled=1
mode=2
work_resolution=100
```

## DLAA-only mode

Do not disable Feeder.

Set:

```ini
enabled=0
```

in `deep-fried-chicken.cfg`, or toggle the DFC `Enabled` control in the ReShade interface.

That produces:

```text
DLAA only
```

Set `enabled=1` again for:

```text
DLAA -> DLSS 5 Neural Rendering
```

For complete DFC disarming, set:

```ini
arm=0
```

and restart the game/bridge process.

## Conflicts

Use exactly one Neural Rendering provider. The upgrade script retires known conflicting add-ons such as:

```text
renodx-dlss5.addon64
renodx-dlss.addon64
alexs-toolkit.addon64
dlssnr-cascade*.addon64
dlss5-dx11-bridge.addon64
```

Avoid OptiScaler acting as another feature-1/NR consumer at the same time.

If alternating-frame flicker/cadence problems appear, disable NVIDIA Smooth Motion before changing the core bridge configuration.
