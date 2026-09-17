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
- six reconstruction choices: DLAA Native, Custom Ultra Quality, Quality, Balanced, Performance and Ultra Performance;
- the tested temporal synchronization required for stable DLSS reconstruction;
- automatic startup stabilization to prevent the cold-start vibration seen at low render resolutions;
- the tested DLSS 5 Neural Rendering runtime;
- a compact **GTA IV DLSS** panel inside ReShade for normal settings;
- a master **DLSS / DLAA processing** switch that can return the game to native raw rendering without restarting;
- folded **Advanced** and **Diagnostics** sections so normal controls stay uncluttered;
- `DLSS-Full-Control.bat` for launch, repair, status and diagnostics only.

**Neural Rendering is installed but OFF by default. DLSS / DLAA processing is ON by default.**

## Install

Copy:

```text
install/Install-DLSS-Full.bat
```

beside `GTAIV.exe` and run it.

The public defaults are:

```text
DLSS / DLAA processing:  ON
DLSS quality:             Quality
Neural Rendering:        OFF
NR passes:                1
```

The installer does not ask you to choose quality because normal configuration is done live inside ReShade.

## Configure DLSS in ReShade

Press **Home**, then open:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

This is the project's single normal settings surface. The inner **GTA IV DLSS** section is opened by default when the overlay appears. ReShade itself owns the outer Add-ons container.

### DLSS / DLAA processing

Use the master **DLSS / DLAA processing** checkbox to disable or re-enable the entire reconstruction path in-game.

Turning it OFF is deliberately staged instead of cutting the renderer out immediately:

```text
current DLSS/DLAA mode
 -> normal transition to DLAA Native / true native render size
 -> 30 stable native frames
 -> temporal jitter OFF
 -> 400 ms drain for the bridge config poll
 -> raw native GTA frame passthrough
```

Once the panel reports **OFF - native raw rendering**, Neural Rendering, temporal jitter, DLSS Super Resolution and DLAA evaluation are all disabled. The game remains at native render/output resolution.

Master OFF is **session-only**. If GTA IV is closed while processing is OFF, the next launch restores the previously selected reconstruction mode and Neural Rendering state, starts processing ON, and lets the normal `1485×835` startup stabilization run. This avoids bringing the cold-start vibration back.

Turning processing back ON during the same session restores the saved reconstruction mode and Neural Rendering choice.

### Reconstruction

The **Reconstruction** selector exposes all six public modes:

| Mode | Meaning |
|---|---|
| DLAA Native | Native-resolution DLAA; no Super Resolution scaling. |
| Custom Ultra Quality (77%) | Highest internal render resolution of the upscaling modes. |
| Quality | Recommended general-purpose default. |
| Balanced | Middle ground between image quality and performance. |
| Performance | Lower internal render resolution for more GPU headroom. |
| Ultra Performance | Lowest internal render resolution; mainly useful when maximum performance is needed. |

Mode changes apply live and are saved automatically.

### Neural Rendering

Use **Enable Neural Rendering** to turn DLSS 5 Neural Rendering OFF or ON.

The setting is saved automatically and the runtime switch is applied through the normal safe frame/config path rather than directly inside the UI callback.

### Advanced

The folded **Advanced** section contains the Neural Rendering pass count.

The tested public default is **1 pass**. Higher pass counts remain available for experimentation, but they can cost significant performance.

### Diagnostics

The folded **Diagnostics** section shows the currently requested GTA render size, the live DXVK source size, the physical output/presenter size, and requested/applied reconstruction modes. It is useful for confirming that a live mode change actually reached the expected internal resolution.

## DLSS tools helper

`DLSS-Full-Control.bat` is not a settings menu.

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

The installer uses `1485×835` automatically. You do not need to change internal render resolutions yourself.

The master-processing switch does not persist an OFF state across launches specifically so this startup stabilization remains available on every new session.

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
 -> DLSS 4.5 Super Resolution / DLAA
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
5. change between DLAA/DLSS modes and optionally Neural Rendering live from that panel;
6. optionally toggle **DLSS / DLAA processing** OFF, wait for **OFF - native raw rendering**, then turn it ON again to verify the saved mode is restored.

If you need log-level proof, see [`VERIFY.md`](VERIFY.md).

## Technical identities

For exact reproduction and debugging, the rendering core corresponds to these internal checkpoints:

```text
Temporal synchronization: A3-S2
Startup stabilization:    A3-S5
Frozen core checkpoint:   57a8bd2ede8d7b4b721b1981bc0e8a7e6cbe084f
Public UX/master v2 pin:  ddc95ef594a960820a70eee37767a2fc9583fb90
```

The production build keeps the frozen temporal/startup rendering core intact, then applies pinned post-checkpoint stages for the public ReShade controls, the startup-prime release fix, and the hardware-validated UX/master v2 behavior. The master switch changes state sequencing and the settings surface; it does not alter the frozen A3-S2 jitter math, motion-vector scaling, or reconstruction ordering.

Those internal codes are intentionally kept out of the normal installation instructions because they describe engineering checkpoints, not extra user-selectable installation steps.
