# Installers

For most users, follow these four steps in order:

| Step | What to install | What it gives you |
|---|---|---|
| **1** | **FusionFix 5.0.1** | Clean modern GTA IV renderer baseline. |
| **2** | **`Install-DLAA.bat`** | DLAA plus the bridge/ReShade/motion-data foundation required by the rest of the project. |
| **3** | **ReShade controls fix** | Makes the Home overlay, mouse and keyboard work through the separate renderer process. |
| **4** | **`Install-DLSS-Full.bat`** | DLSS 4.5 Super Resolution, automatic startup stabilization, and DLSS 5 Neural Rendering installed OFF by default. |

The root [`README.md`](../README.md) is the main step-by-step guide.

## Step 2 — DLAA

`Install-DLAA.bat` creates the known-good DLAA baseline from a clean FusionFix installation.

It installs `nvngx_dlss.dll` 310.9.1 and the required bridge/ReShade/Feeder foundation.

**Finished when:** GTA IV launches normally and `.trex\dlss5-feed.log` reports DLAA frames being delivered.

## Step 3 — ReShade controls fix

Open:

```text
../tools/reshade-bbridge-input/
```

Build the patch, then **right-click `INSTALL.bat` → Run as administrator**.

**Finished when:** pressing Home opens ReShade and mouse/keyboard input works inside it.

Do not continue to Step 4 until that works.

## Step 4 — DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering

`Install-DLSS-Full.bat` adds:

- five DLSS Super Resolution quality modes;
- temporal synchronization needed for stable reconstruction;
- automatic `1485×835` startup stabilization;
- automatic return to the saved DLSS quality mode;
- the tested `nvngx_dlssnr.dll` 310.8.0-RTX40 Neural Rendering runtime;
- a **GTA IV DLSS** panel inside ReShade for normal settings;
- `DLSS-Full-Control.bat` for launch/repair/diagnostics only.

Defaults after install:

```text
DLSS quality:       Quality
Neural Rendering:  OFF
NR passes:          1
```

### Normal settings

Open ReShade with **Home**, then go to:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

Use that panel for:

- **Neural Rendering OFF / ON**;
- **Neural Rendering passes (advanced)** — 1 is the tested public default;
- **DLSS Super Resolution quality** — Custom Ultra Quality (77%), Quality, Balanced, Performance, Ultra Performance.

These settings are saved automatically. There is no need to close the game or use a BAT file to change them.

### Tools helper

`DLSS-Full-Control.bat` is intentionally not a second settings menu. It provides:

```text
L  Launch with startup stabilization pre-armed
R  Repair / re-arm startup stabilization
S  Show current DLSS / Neural Rendering status
D  Open the DLSS diagnostic log
```

The repair action preserves your saved quality, Neural Rendering state and pass count.

### About names seen in logs/source

The installer source and logs still contain internal engineering labels such as `A3-S2`, `A3-S5` and `M3K`. They are not extra steps:

- `A3-S2` = temporal synchronization fix;
- `A3-S5` = automatic startup stabilization;
- `M3K` = internal project integration namespace.

Normal users do not need to configure those directly.

## Backup

`Backup-Working-Stack.bat` snapshots the current integration, including the bridge, ReShade configuration, DLSS configuration and Neural Rendering runtime.

The installation scripts also create timestamped rollback backups before replacing runtime files.
