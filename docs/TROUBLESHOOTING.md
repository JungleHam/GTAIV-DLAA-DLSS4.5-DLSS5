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

Do not try to repair this by changing jitter phase count, projection math or jitter sign. The tested temporal-synchronization implementation is already hardware validated.

Internal source/debug names:

```text
A3-S2 = temporal synchronization
A3-S5 = startup stabilization
```

## The installer says local PE hashes differ

This can be normal across Visual Studio/MSVC versions.

The installer pins the exact source checkpoints and runs the build/test gates. The recorded bridge/Feeder/shim SHA256 values identify the hardware-tested reference binaries; a newer compiler can still produce different bytes from the same validated source.

A source checkout/build/test failure matters. A PE hash difference by itself does not necessarily mean the build is wrong.

## Neural Rendering is installed but not active

That is the expected default after Step 4.

Use `DLSS-Full-Control.bat` and choose:

```text
N  Turn NR ON
```

To disable it again, choose:

```text
O  Turn NR OFF
```

For troubleshooting only, the underlying config is:

```ini
Mode=0   ; NR OFF
Mode=2   ; NR ON
NRPasses=1
```

## Neural Rendering ON but it does not start

Check:

```text
.trex\m3k\m3k-nvngx.dll
.trex\m3k\nvngx_dlssnr.dll
.trex\m3k-nr.ini
.trex\dlss5-feed.log
```

The tested NR DLL hash is:

```text
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

The current validated NR package targets RTX 40/50. Direct project validation is on RTX 4070 Ti SUPER, and the tested runtime requires NVIDIA driver 615.00 or newer when NR is enabled.

Successful logs may include:

```text
M3K-A0: DLSS NR runtime found
M3K-A0: feature 18 creation SUCCESS
M3K-A1: feature 18 evaluation SUCCESS
```

Here, `feature 18` is simply the internal NGX name for **DLSS 5 Neural Rendering**.

## Neural Rendering is much slower than SR alone

That is expected on RTX 40 hardware. Neural Rendering adds another substantial neural processing stage before Super Resolution.

The validated normal configuration is one NR pass:

```ini
NRPasses=1
```

Do not add a second NR provider or extra neural pass while diagnosing performance.

## Need DLSS Super Resolution without Neural Rendering

Use `DLSS-Full-Control.bat` and choose:

```text
O  Turn NR OFF
```

Super Resolution remains enabled.

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
