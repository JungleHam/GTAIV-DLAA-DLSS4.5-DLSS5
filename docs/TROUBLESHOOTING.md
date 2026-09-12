# Troubleshooting

## Legal screen hang / catastrophic graphics

Do not return to the known-bad experimental paths unless you are intentionally debugging them:

- dgVoodoo D3D9 -> D3D11;
- direct in-process x86 DXVK with FusionFix in this setup.

The successful architecture uses b-bridge with its 64-bit server.

## ReShade shader error 123 / shaders not found

Use simple search paths:

```ini
EffectSearchPaths=.\reshade-shaders\Shaders
TextureSearchPaths=.\reshade-shaders\Textures
```

Do not use trailing `\**` in this bridge setup.

## Home does nothing after Step 3

First inspect `.trex\ReShade.log`.

If it contains:

```text
Cannot capture input for window ... created by a different process
```

then the stock/unpatched ReShade DLL is still loading. Step 3 is not complete, regardless of what an older installer window may have reported.

The patched build should instead log lines beginning with:

```text
b-bridge input relay: accepting foreign render window
b-bridge input relay: handshake complete
```

Use the current `BUILD.bat` and `INSTALL.bat` from `tools/reshade-bbridge-input/`. The current build script performs a clean rebuild and verifies that the compiled DLL contains the patch marker; the installer verifies that the global `C:\ProgramData\ReShade\ReShade64.dll` is byte-for-byte identical to the patched DLL before claiming success.

## ReShade UI visible but mouse/keyboard dead

Install the patch under:

```text
tools/reshade-bbridge-input/
```

and ensure `.trex\bridge.conf` contains:

```ini
client.DirectInput.forward.mousePolicy = 3
client.DirectInput.forward.keyboardPolicy = 3
```

If the patched ReShade log shows `accepting foreign render window` but never shows `handshake complete`, the patched DLL loaded but the b-bridge message-channel handshake failed. Check `bridge.conf` and the bridge client logs next.

If you are debugging only the original POC and the handshake succeeds but no events arrive, `client.hookMessagePump = True` is a secondary test. It is not part of the normal known-good setup.

## DFC installed but Neural Rendering is not running

Check:

```text
.trex\dlss5-feed.log
.trex\deep-fried-chicken.log
```

DFC should be armed and Feature 18 should be created successfully.

Confirm:

```ini
arm=1
enabled=1
safe_neutral_start=0
```

and make sure no second Neural Rendering provider is loaded.

## DFC add-on disappears after installation

Security software may quarantine hook/injection add-ons. Check your antivirus/Defender history.

Do not automatically add broad exclusions. Restore the file only if you trust the source and understand why it was flagged.

## Flicker every other frame

Turn NVIDIA Smooth Motion off first.

## One motion-vector probe is zero

Do not diagnose the whole pipeline from a single static-scene probe. In the tested setup isolated low/zero-MV probes occurred while surrounding probes were healthy and neural processing continued successfully.

If motion-vector and depth probes remain zero/flat continuously during actual gameplay, that is different: fix the ReShade depth/motion-vector inputs before judging DLAA quality or enabling Neural Rendering.

## Neural Rendering performance is much lower than DLAA

Expected. The tested native one-pass Neural Rendering path was substantially more expensive than DLAA-only.

Return to the known-good baseline before tuning:

- one pass;
- native / 100% neural work resolution;
- motion stability around the DFC default/tested value;
- texture boost off;
- no extra neural provider.

## Need pure DLAA

Keep Feeder on and set DFC:

```ini
enabled=0
```

Do not disable Feeder: Feeder is what provides the working DLAA path.
