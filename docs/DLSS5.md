# DLSS 5 Neural Rendering — native M3K path

The current project does **not** use Deep Fried Chicken.

DLSS 5 Neural Rendering is integrated directly into the project’s A3-S5 Feeder/M3K path and is installed together with DLSS 4.5 Super Resolution by:

```text
install/Install-DLSS-Full.bat
```

## Required base

Complete the normal flow first:

```text
FusionFix -> DLAA -> ReShade input fix -> combined SR + NR module
```

The combined installer places the NR runtime at:

```text
GTAIV\.trex\m3k\nvngx_dlssnr.dll
```

and verifies the tested RTX40-compatible DLL hash:

```text
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

## Default state

NR is installed but **OFF** after Step 4:

```ini
Mode=0
NRPasses=1
```

This means DLSS 4.5 Super Resolution can run normally while Feature 18 remains disabled.

## Enable Neural Rendering

Close GTA IV and run:

```text
DLSS-Full-Control.bat
```

Choose:

```text
N  Turn NR ON
```

That sets:

```ini
Mode=2
NRPasses=1
```

The production rendering order is:

```text
GTA IV true source color
 -> native DLSS 5 Neural Rendering / NGX Feature 18
 -> DLSS 4.5 Super Resolution
 -> presenter resolution
```

The NR pass uses the same source-resolution depth/motion-vector/jitter domain as the SR stage.

## Disable Neural Rendering

Close GTA IV, run the same control helper, and choose:

```text
O  Turn NR OFF
```

That writes:

```ini
Mode=0
```

SR remains enabled.

## Runtime / GPU notes

The current tested runtime is:

```text
nvngx_dlssnr.dll 310.8.0-RTX40
```

It is the community RTX 40/50-compatible build with Ada (`sm_89`) support. The project’s direct hardware validation is on an RTX 4070 Ti SUPER.

The runtime reports a minimum NVIDIA driver of **615.00**. Use 615.00 or newer before enabling NR.

The current validated installer does not automatically select the RTX 20/30 SF variants; those are outside this project’s tested path.

## Verification

Open:

```text
GTAIV\.trex\dlss5-feed.log
```

Successful native NR validation has produced evidence such as:

```text
M3K-A0: DLSS NR runtime found
M3K-A0: feature 18 creation SUCCESS
M3K-A1: feature 18 evaluation SUCCESS
M3K-A2-S2.6: NR18 -> DLAA running ...
```

A healthy Mode 2 session should continue evaluating NR rather than repeatedly failing/recreating Feature 18.

There is no `deep-fried-chicken.log`, DFC config, DFC add-on, or DFC ReShade tab in the current implementation.
