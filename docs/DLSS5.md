# DLSS 5 Neural Rendering

DLSS 5 Neural Rendering is included in **Step 4** together with DLSS 4.5 Super Resolution.

You do not install a separate Neural Rendering mod after that step.

## What gets installed

The combined Step 4 installer downloads and verifies:

```text
nvngx_dlssnr.dll 310.8.0-RTX40
```

and places it at:

```text
GTAIV\.trex\m3k\nvngx_dlssnr.dll
```

The runtime is installed automatically, but Neural Rendering starts **OFF by default**.

## Turn Neural Rendering ON or OFF

Open ReShade with **Home**, then go to:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

Use the **Neural Rendering** checkbox.

- unchecked = Neural Rendering OFF;
- checked = Neural Rendering ON.

The setting is saved automatically. You do not need to close GTA IV or run a BAT file to change it.

When enabled, the rendering order is:

```text
GTA IV internal image
 -> DLSS 5 Neural Rendering
 -> DLSS 4.5 Super Resolution
 -> display/output resolution
```

## Neural Rendering passes

The same ReShade panel contains:

```text
Neural Rendering passes (advanced)
```

The current tested public default is **1 pass**.

Higher pass counts remain available for experimentation, but they may hitch while warming and can cost significant performance.

## Why it is OFF by default

Neural Rendering adds a substantial GPU workload, especially on RTX 40 hardware. Keeping it OFF by default means Step 4 can first be verified as a stable DLSS Super Resolution installation before the extra neural pass is enabled.

## GPU/runtime notes

The current tested runtime is:

```text
nvngx_dlssnr.dll 310.8.0-RTX40
```

It is the RTX 40/50-compatible build used by this project. Direct project validation is on RTX 4070 Ti SUPER.

The runtime reports a minimum NVIDIA driver of **615.00**. Use 615.00 or newer before enabling Neural Rendering.

Other GPU-generation Neural Rendering variants are outside the current validated install path.

## Underlying config

Normal users should use the ReShade checkbox. For troubleshooting, the same setting is stored internally as:

```ini
Mode=0       ; Neural Rendering OFF
Mode=2       ; Neural Rendering ON
NRPasses=1   ; tested public default
```

The `Mode` number is an internal project setting, not a DLSS quality level.

The ReShade panel writes this configuration automatically, while the actual runtime transition is applied through the normal safe frame/config path.

## Tools helper

`DLSS-Full-Control.bat` does **not** control Neural Rendering anymore.

It is limited to:

```text
L  Launch with startup stabilization pre-armed
R  Repair / re-arm startup stabilization
S  Show current status
D  Open the diagnostic log
```

## Names you may see in logs

Older engineering notes and runtime logs may use:

- `M3K` — the project's internal DLSS integration namespace;
- `Feature 18` or `NR18` — NVIDIA's internal NGX identifier for Neural Rendering;
- `A3-S2` — the project's temporal synchronization checkpoint;
- `A3-S5` — the project's automatic startup-stabilization checkpoint.

For normal use, all of these simply belong to the single **DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering** Step 4 installation.

## Verification

Open:

```text
GTAIV\.trex\dlss5-feed.log
```

A healthy NR-enabled session should report successful Neural Rendering initialization/evaluation rather than repeatedly creating and failing the feature.

The log may use internal wording such as `feature 18 creation SUCCESS` or `feature 18 evaluation SUCCESS`. In user-facing terms, that means **DLSS 5 Neural Rendering initialized and ran successfully**.

See [`VERIFY.md`](VERIFY.md) for exact debug strings.
