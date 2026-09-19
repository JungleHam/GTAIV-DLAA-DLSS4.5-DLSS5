# Troubleshooting

This page uses the same user-facing names as the main README. Internal log/source names are shown only where they help identify a problem.

## Legal screen hang / catastrophic graphics

Do not return to known-bad experimental paths unless you are intentionally debugging them:

- dgVoodoo D3D9 -> D3D11;
- direct in-process x86 DXVK with FusionFix in this setup.

The supported architecture uses b-bridge with its separate 64-bit renderer process.

## ReShade shader error 123 / shaders not found

Use simple search paths:

```ini
EffectSearchPaths=.\reshade-shaders\Shaders
TextureSearchPaths=.\reshade-shaders\Textures
```

Do not append `\**` in this bridge setup.

## Home does nothing after Step 3

Inspect:

```text
.trex\ReShade.log
```

If it contains:

```text
Cannot capture input for window ... created by a different process
```

then stock/unpatched ReShade is still loading.

Use the current `BUILD.bat`, then **right-click `INSTALL.bat` -> Run as administrator** from:

```text
tools\reshade-bbridge-input\
```

Expected patched-log evidence may include:

```text
b-bridge input relay: accepting foreign render window
b-bridge input relay: handshake complete
```

## ReShade UI visible but mouse/keyboard dead

Confirm `.trex\bridge.conf` contains:

```ini
client.DirectInput.forward.mousePolicy = 3
client.DirectInput.forward.keyboardPolicy = 3
```

If ReShade accepts the foreign window but never logs `handshake complete`, troubleshoot the bridge input-message path next.

## GTA IV DLSS panel is missing

After Step 4, open:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

If the **GTA IV DLSS** section is missing, Step 4 likely did not install the current public Feeder build.

Re-run `Install-DLSS-Full.bat` after confirming Step 3 works.

The current panel should contain:

- Neural Rendering OFF/ON;
- Neural Rendering passes (advanced);
- DLSS Super Resolution quality.

## DLSS starts with vibration

The current fix is **automatic startup stabilization**:

```text
1485×835
180 synchronized frames
then your saved DLSS quality mode
```

Use `DLSS-Full-Control.bat` and launch with `L` so the stabilization resolution is written before GTA starts.

Expected log evidence may include:

```text
M3K-A3-S5: STARTUP PRIME armed 1485x835
M3K-A3-S5: STARTUP PRIME COMPLETE after 180 synchronized SR frames
```

Those internal strings mean the **startup stabilization** ran successfully.

If the startup settings were changed or damaged, use:

```text
DLSS-Full-Control.bat -> R
```

The repair action restores only startup-stabilization settings and preserves DLSS quality, Neural Rendering state and pass count.

Do not try to repair this by changing jitter phase count, projection math or jitter sign. The tested temporal-synchronization implementation is already hardware validated.

Internal source/debug names:

```text
A3-S2 = temporal synchronization
A3-S5 = startup stabilization
```

## The installer says local PE hashes differ

This can be normal across Visual Studio/MSVC versions.

The installer pins the frozen rendering core and runs its build/test gates. The public Feeder also contains the newer ReShade control panel, so its bytes are expected to differ from the older pre-UI hardware-reference Feeder even when the rendering core is unchanged.

A source checkout/build/test failure matters. A PE hash difference by itself does not necessarily mean the build is wrong.

## Neural Rendering is installed but not active

That is the expected default after Step 4.

Open:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

and check **Neural Rendering**.

To disable it again, uncheck the same box.

The ReShade setting is saved automatically. For troubleshooting only, the underlying config is:

```ini
Mode=0   ; NR OFF
Mode=2   ; NR ON
NRPasses=1
```

The runtime switch is intentionally applied through the normal safe frame/config path, so it can take up to the normal config-poll interval after clicking the checkbox.

## Neural Rendering ON but it does not start

Check:

```text
.trex\m3k\m3k-nvngx.dll
.trex\m3k\nvngx_dlssnr.dll
.trex\m3k-nr.ini
.trex\dlss5-feed.log
```

Check the installed NR DLL against the GPU-specific value:

```text
RTX 40 compatibility:
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05

RTX 50 NVIDIA-signed:
E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

For RTX 50, the DLL must also have a valid NVIDIA Authenticode signature. Direct project validation is on RTX 4070 Ti SUPER, and the tested runtime requires NVIDIA driver 615.00 or newer when NR is enabled.

Successful logs may include:

```text
M3K-UI: ReShade requested Neural Rendering ON
M3K-A0: DLSS NR runtime found
M3K-A0: feature 18 creation SUCCESS
M3K-A1: feature 18 evaluation SUCCESS
```

Here, `feature 18` is simply the internal NGX name for **DLSS 5 Neural Rendering**.

## Neural Rendering is much slower than Super Resolution alone

That is expected on RTX 40 hardware. Neural Rendering adds another substantial neural processing stage before Super Resolution.

The validated normal configuration is one NR pass. In the ReShade panel, leave:

```text
Neural Rendering passes (advanced) = 1
```

while diagnosing performance.

Higher pass counts are experimental and intentionally not the public default.

## Need DLSS Super Resolution without Neural Rendering

Open the **GTA IV DLSS** ReShade panel and turn **Neural Rendering OFF**.

Super Resolution remains enabled.

## DLSS quality will not change

Use:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

and select one of:

```text
Custom Ultra Quality (77%)
Quality
Balanced
Performance
Ultra Performance
```

The setting should apply live and save automatically.

If a requested mode is unsupported at the current output/input combination, the integration rejects it safely and keeps the working mode.

## Need pure DLAA again

Step 4 replaces the Step 2 pure-DLAA runtime integration with the Super-Resolution-capable stack.

To return to the original Step 2 baseline, restore the timestamped pre-Step-4 backup created by `Install-DLSS-Full.bat`.

## Flicker every other frame

Turn NVIDIA Smooth Motion off first before changing the project's tested temporal-synchronization setup.

## One motion-vector probe is zero

Do not judge the whole pipeline from one static-scene sample.

If motion-vector and depth data stay flat during actual camera/object movement, fix the ReShade depth/motion inputs before judging DLAA, Super Resolution or Neural Rendering quality.

## Terminology seen in old notes/logs

| Internal wording | Plain-English meaning |
|---|---|
| `A3-S2` | temporal synchronization |
| `A3-S5` / `startup prime` | automatic startup stabilization |
| `M3K` | internal project integration namespace |
| `Feature 18` / `NR18` | DLSS 5 Neural Rendering |
| `true source` | actual internal game render resolution |
| `presenter` | final display/output resolution |
