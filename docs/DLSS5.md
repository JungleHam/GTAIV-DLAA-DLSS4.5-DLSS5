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

## Turn Neural Rendering ON

1. Close GTA IV.
2. Run:

```text
DLSS-Full-Control.bat
```

3. Choose:

```text
N  Turn NR ON
```

4. Choose `L` to launch GTA IV through the recommended startup-stabilization path.

When enabled, the rendering order is:

```text
GTA IV internal image
 -> DLSS 5 Neural Rendering
 -> DLSS 4.5 Super Resolution
 -> display/output resolution
```

The current validated configuration uses **one Neural Rendering pass**.

## Turn Neural Rendering OFF

1. Close GTA IV.
2. Run `DLSS-Full-Control.bat`.
3. Choose:

```text
O  Turn NR OFF
```

DLSS 4.5 Super Resolution remains active.

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

## How the config represents ON/OFF

Normal users should use `DLSS-Full-Control.bat`, but for troubleshooting the underlying configuration is:

```ini
Mode=0       ; Neural Rendering OFF
Mode=2       ; Neural Rendering ON
NRPasses=1   ; use one NR pass
```

The `Mode` number is an internal project setting, not a DLSS quality level.

## Names you may see in logs

Older engineering notes and runtime logs may use:

- `M3K` — the project's internal DLSS integration namespace;
- `Feature 18` or `NR18` — NVIDIA's internal NGX identifier for the Neural Rendering feature;
- `A3-S2` — the project's temporal synchronization checkpoint;
- `A3-S5` — the project's automatic startup-stabilization checkpoint.

For normal use, all of these simply belong to the single **DLSS 4.5 SR + DLSS 5 Neural Rendering** Step 4 installation.

## Verification

Open:

```text
GTAIV\.trex\dlss5-feed.log
```

A healthy NR-enabled session should report successful Neural Rendering initialization/evaluation rather than repeatedly creating and failing the feature.

The log may use internal wording such as `feature 18 creation SUCCESS` or `feature 18 evaluation SUCCESS`. In user-facing terms, that means **DLSS 5 Neural Rendering initialized and ran successfully**.

See [`VERIFY.md`](VERIFY.md) for exact debug strings.
