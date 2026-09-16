# Verification

The current stack is verified primarily through:

```text
GTAIV\.trex\dlss5-feed.log
```

There is no Deep Fried Chicken log in the current implementation.

## Step 2 — DLAA baseline

A healthy base should show evidence equivalent to:

```text
DLSS5_MV_PROVIDER=3 (LumeniteFX Kernel)
feature ready: <output resolution> DLAA ...
frame ... delivered
```

The exact resolution depends on the game output.

Healthy runtime probes should show usable depth and non-trivial motion-vector data while moving through the scene.

## Step 4 — DLSS 4.5 Super Resolution

The combined module should first establish the A3-S5 startup prime:

```text
M3K-A3-S5: STARTUP PRIME armed 1485x835
M3K-SR-LIVE: STARTUP PRIME: Quality contract ... true-source=1485x835 ACCEPTED
M3K-A3-S5: prime synchronized to A3-S2 jitter ... at 1485x835
M3K-A3-S5: STARTUP PRIME COMPLETE after 180 synchronized SR frames
```

It should then switch to the saved SR profile:

```text
M3K-SR-LIVE: ACTIVE <saved mode> ... -> <presenter resolution>
```

The bridge log should continue to show synchronized draw-boundary jitter rather than upload-time partial jitter.

## DLSS 5 Neural Rendering OFF

Default combined-module state:

```ini
Mode=0
NRPasses=1
```

`nvngx_dlssnr.dll` is still installed at:

```text
.trex\m3k\nvngx_dlssnr.dll
```

but Feature 18 is not evaluated.

## DLSS 5 Neural Rendering ON

Use `DLSS-Full-Control.bat` and choose `N`.

Expected configuration:

```ini
Mode=2
NRPasses=1
```

The proven native M3K path has produced evidence such as:

```text
M3K-A0: DLSS NR runtime found
M3K-A0: feature 18 creation SUCCESS
M3K-A1: feature 18 evaluation SUCCESS
M3K-A1: DLAA running after NR
M3K-A2-S2.6: NR18 -> DLAA running ...
```

A healthy session should continue evaluating Feature 18 rather than repeatedly creating/failing it.

For a clean A/B comparison:

1. close GTA IV;
2. use `DLSS-Full-Control.bat` → `O` for NR OFF;
3. capture the same scene;
4. close GTA IV;
5. use `DLSS-Full-Control.bat` → `N` for NR ON;
6. launch with the same SR profile and scene.

Useful visual comparison targets include thin fences/power lines, foliage, distant detail, night lighting, motion stability and ghosting.

## ReShade input patch

Step 3 is verified by behavior, not merely by copied files:

- Home opens/closes ReShade;
- the ReShade cursor moves;
- mouse clicks and keyboard input work;
- the DLSS5-Feeder controls are interactive;
- closing the overlay returns input to GTA IV.

The patched ReShade log may also contain messages prefixed with:

```text
b-bridge input relay:
```

If Home does nothing, do not continue to Step 4 until the input patch is fixed.
