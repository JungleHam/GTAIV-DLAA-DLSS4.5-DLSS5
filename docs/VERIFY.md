# Verification

You do not need to understand the project's internal stage names to verify the install.

Main runtime log:

```text
GTAIV\.trex\dlss5-feed.log
```

## Step 2 — Verify DLAA

A healthy DLAA baseline should report that the motion/depth provider is active and DLAA frames are being delivered.

Typical log evidence:

```text
DLSS5_MV_PROVIDER=3 (LumeniteFX Kernel)
feature ready: <output resolution> DLAA ...
frame ... delivered
```

For a normal user, the important checks are:

- GTA IV launches normally;
- DLAA is active at the native/output resolution;
- the image is stable during camera movement.

## Step 3 — Verify the ReShade controls fix

This step is verified by behavior:

- Home opens/closes ReShade;
- the ReShade cursor moves;
- mouse clicks work;
- keyboard input works inside the overlay;
- closing the overlay returns control to GTA IV.

If Home does nothing, do not continue to Step 4.

## Step 4 — Verify DLSS Super Resolution

Launch through:

```text
DLSS-Full-Control.bat
```

and choose `L`.

Expected user-visible behavior:

1. GTA IV starts through the brief automatic startup-stabilization phase;
2. the game switches automatically to your saved DLSS quality mode;
3. the image remains stable instead of entering the old cold-start vibration state.

### Exact debug strings

The runtime still uses internal engineering labels in the log. A successful startup may include:

```text
M3K-A3-S5: STARTUP PRIME armed 1485x835
M3K-SR-LIVE: STARTUP PRIME: Quality contract ... true-source=1485x835 ACCEPTED
M3K-A3-S5: prime synchronized to A3-S2 jitter ... at 1485x835
M3K-A3-S5: STARTUP PRIME COMPLETE after 180 synchronized SR frames
M3K-SR-LIVE: ACTIVE <saved mode> ...
```

Plain-English translation:

- `A3-S5` / `STARTUP PRIME` = **automatic startup stabilization**;
- `A3-S2 jitter` = **temporal synchronization**;
- `true-source` = **the game's actual internal render resolution**;
- `M3K-SR-LIVE: ACTIVE` = **DLSS Super Resolution is running in the selected mode**.

These are log labels, not steps you need to install separately.

## Verify Neural Rendering OFF

Neural Rendering is OFF by default after Step 4.

The config will contain:

```ini
Mode=0
NRPasses=1
```

The NR runtime is still installed at:

```text
.trex\m3k\nvngx_dlssnr.dll
```

so you can enable it later without reinstalling Step 4.

## Verify Neural Rendering ON

Close GTA IV, run `DLSS-Full-Control.bat`, choose `N`, then launch with `L`.

The config becomes:

```ini
Mode=2
NRPasses=1
```

Successful logs may contain internal strings such as:

```text
M3K-A0: DLSS NR runtime found
M3K-A0: feature 18 creation SUCCESS
M3K-A1: feature 18 evaluation SUCCESS
M3K-A1: DLAA running after NR
M3K-A2-S2.6: NR18 -> DLAA running ...
```

Plain-English translation:

- `feature 18` / `NR18` = **DLSS 5 Neural Rendering**;
- `creation SUCCESS` = the Neural Rendering feature initialized;
- `evaluation SUCCESS` = the Neural Rendering pass actually ran;
- `NR18 -> DLAA/SR` = Neural Rendering completed before the following DLSS reconstruction stage.

A healthy session should continue evaluating Neural Rendering rather than repeatedly creating/failing it.

## Simple NR A/B test

To compare NR visually without changing anything else:

1. close GTA IV;
2. run `DLSS-Full-Control.bat` and choose `O` for NR OFF;
3. launch and capture a scene;
4. close GTA IV;
5. run the helper and choose `N` for NR ON;
6. launch the same SR quality mode and compare the same scene.

Good comparison targets include thin fences/power lines, foliage, distant detail, night lighting, motion stability and ghosting.
