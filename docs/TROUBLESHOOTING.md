# Troubleshooting

## Legal screen hang / catastrophic graphics

Do not return to known-bad experimental paths unless you are intentionally debugging them:

- dgVoodoo D3D9 -> D3D11;
- direct in-process x86 DXVK with FusionFix in this setup.

The successful architecture uses b-bridge with its 64-bit renderer process.

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

Expected patched-log evidence includes lines beginning with:

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

If ReShade accepts the foreign window but never logs `handshake complete`, troubleshoot the b-bridge input-message channel next.

## DLSS 4.5 SR starts with vibration

The accepted fix is A3-S5's automatic startup prime:

```text
1485x835
180 synchronized SR frames
then saved SR profile
```

Use `DLSS-Full-Control.bat` and launch with `L` so `1485x835` is written before GTA starts.

Expected log evidence:

```text
M3K-A3-S5: STARTUP PRIME armed 1485x835
M3K-A3-S5: STARTUP PRIME COMPLETE after 180 synchronized SR frames
```

Do not try to repair this by changing A3-S2 jitter phase count, projection math or jitter sign. The accepted A3-S2 draw-boundary architecture is already hardware-validated.

## DLSS Full installer says the local PE hashes differ

This can be normal across Visual Studio/MSVC runner revisions.

The installer pins the exact source checkpoints and runs the build/test gates. The recorded bridge/Feeder/shim SHA256 values are the hardware-tested reference binaries, not a requirement that every future local compiler produce byte-identical PE files.

A source checkout/build/test failure is important; a PE hash difference by itself is not.

## NR is installed but not active

This is the expected default.

Open:

```text
.trex\m3k-nr.ini
```

Default:

```ini
Mode=0
NRPasses=1
```

Use `DLSS-Full-Control.bat` and choose `N` to enable the native Feature 18 path:

```ini
Mode=2
NRPasses=1
```

Close GTA IV before changing the mode.

## NR ON but Feature 18 does not start

Check all of the following:

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

The current validated NR package targets RTX 40/50. The direct project validation is RTX 4070 Ti SUPER, and the tested runtime requires NVIDIA driver 615.00 or newer when NR is enabled.

Successful native logs should include evidence equivalent to:

```text
M3K-A0: DLSS NR runtime found
M3K-A0: feature 18 creation SUCCESS
M3K-A1: feature 18 evaluation SUCCESS
```

## NR is much slower than SR alone

Expected on RTX 40. DLSS 5 Neural Rendering adds a substantial native neural pass before SR.

Return to the validated production configuration before experimenting:

```ini
Mode=2
NRPasses=1
```

Do not add a second NR provider or extra neural pass while diagnosing performance.

## Need SR without NR

Use `DLSS-Full-Control.bat` and choose:

```text
O  Turn NR OFF
```

That sets:

```ini
Mode=0
```

DLSS 4.5 Super Resolution remains enabled.

## Need pure DLAA again

The combined Step 4 module changes the bridge/Feeder into the SR-capable A3-S2/A3-S5 stack. For the original Step 2 pure-DLAA baseline, restore the timestamped pre-DLSS-Full backup created by `Install-DLSS-Full.bat`.

## Flicker every other frame

Turn NVIDIA Smooth Motion off first before changing the accepted temporal integration.

## One motion-vector probe is zero

Do not diagnose the whole pipeline from a single static-scene probe. Isolated low/zero samples can occur.

If motion-vector and depth probes stay flat during actual camera/object movement, fix the ReShade depth/MV inputs before judging DLAA, SR or NR quality.
