# GTA IV — DLAA + DLSS 5 Neural Rendering

A reproducible, version-pinned setup for running **real NVIDIA NGX DLAA** in GTA IV, with an optional **DLSS 5 Neural Rendering / NGX Feature 18** stage through Deep Fried Chicken.

This repository is intentionally **not a modpack**. It contains the integration logic, configuration, verification notes, installers, and the ReShade/b-bridge input patch. Third-party projects are fetched from pinned upstream locations, while files that should not be redistributed here are supplied by the user.

> **Status:** tested working stack as of 2026-09-12. Back up your game before using it.

## What works

### DLAA only

```text
GTAIV.exe (32-bit)
  -> FusionFix
  -> b-bridge
  -> NvRemixBridge.exe (64-bit)
  -> DXVK / Vulkan
  -> ReShade 6.8.0 x64
  -> LumeniteFX motion vectors + depth
  -> DLSS5-Feeder 0.15.1
  -> nvngx_dlss.dll 310.9.1
  -> NVIDIA NGX DLAA
```

The tested setup runs DLAA at native output resolution. The successful reference test used **2560×1440**.

### DLAA + DLSS 5 Neural Rendering

```text
... -> NVIDIA NGX DLAA
      -> Deep Fried Chicken 1.7.4
      -> nvngx_dlssnr.dll 310.8.0
      -> NVIDIA NGX Feature 18 / Neural Rendering
```

In this integration, DFC receives the **resolved DLAA output**. Neural Rendering is therefore an additional stage; it does not replace DLAA.

### Fully interactive ReShade + DFC UI through b-bridge

Stock ReShade can render inside `NvRemixBridge.exe`, but normally cannot accept input because the GTA IV window belongs to `GTAIV.exe`.

This repository includes a small source patch for **ReShade 6.8.0** that reconnects b-bridge's already-existing cross-process input path:

```text
GTA IV DirectInput
  -> b-bridge x86 input translator
  -> existing Remix message channel
  -> patched ReShade x64
  -> normal ReShade input system / ImGui
```

With the patch installed, `Home` opens the normal ReShade overlay, mouse/keyboard input works, and the Deep Fried Chicken tab is interactive.

## Installation overview

### 1. Install FusionFix first

Start from a **clean FusionFix 5.0.1** setup. Launch GTA IV once and verify FusionFix itself works.

The project does not redistribute FusionFix. The tested upstream package and hash are recorded in [`manifests/versions.json`](manifests/versions.json).

### 2. Install DLAA

Copy:

```text
install/Install-DLAA.bat
```

into the folder containing `GTAIV.exe`, then run it.

The installer creates a rollback backup, downloads pinned upstream components, installs ReShade 6.8.0 as the Vulkan layer for `NvRemixBridge.exe`, configures Lumenite as Feeder motion-vector provider 3, and enables Feeder DLAA mode at native work resolution.

Read [`docs/DLAA.md`](docs/DLAA.md) first.

### 3. Recommended: install the interactive ReShade patch

From:

```text
tools/reshade-bbridge-input/
```

run:

```text
BUILD.bat
```

Then from an **Administrator** Command Prompt:

```text
INSTALL.bat "X:\path\to\Grand Theft Auto IV\GTAIV"
```

This builds ReShade from the exact 6.8.0 source tag, applies the cross-process input patch, backs up the active global ReShade Vulkan DLL and replaces it with the patched build.

See [`docs/RESHade-INPUT-PATCH.md`](docs/RESHade-INPUT-PATCH.md).

### 4. Optional: upgrade to DLSS 5 Neural Rendering

Supply the two tested files described in [`input/README.md`](input/README.md):

```text
Deep-Fried-Chicken-v1.7.4-checkpoint-70-chicken-assist-reliability.7z
nvngx_dlssnr.dll
```

Then copy:

```text
install/Upgrade-DLSS5-DFC.bat
```

beside `GTAIV.exe` and run it.

## Switching to DLAA only

Do **not** disable Feeder.

Turn off DFC neural processing:

```ini
enabled=0
```

in:

```text
GTAIV\.trex\deep-fried-chicken.cfg
```

or toggle it through the Deep Fried Chicken ReShade tab.

Effective modes:

```text
DFC Enabled OFF = DLAA only
DFC Enabled ON  = DLAA -> DLSS 5 Neural Rendering
```

`arm=0` fully disarms DFC and requires a restart. That is useful for troubleshooting, but not necessary for ordinary DLAA/NR A/B testing.

## Known-good pinned stack

| Component | Tested version |
|---|---|
| FusionFix | 5.0.1 |
| b-bridge | 0.1.0 |
| ReShade | 6.8.0 Full Add-On Support |
| DLSS5-Feeder | 0.15.1 |
| LumeniteFX | `f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9` |
| ReShade shader headers | `6db142b4b1a05c764222e5b0bd9a644b7ccfe1dc` |
| `nvngx_dlss.dll` | 310.9.1 |
| Deep Fried Chicken | 1.7.4 checkpoint 70 |
| `nvngx_dlssnr.dll` | 310.8.0 |

Exact package URLs and hashes are in [`manifests/versions.json`](manifests/versions.json).

## Verification

For DLAA, inspect:

```text
GTAIV\.trex\dlss5-feed.log
```

Expected evidence includes:

```text
DLSS5_MV_PROVIDER=3
feature ready: ... DLAA
```

For Neural Rendering, inspect:

```text
GTAIV\.trex\deep-fried-chicken.log
```

Expected evidence includes:

```text
feature 18 ... Success
standalone feature 18 created
standalone neural frame succeeded
```

See [`docs/VERIFY.md`](docs/VERIFY.md).

## Important limitations

- GTA IV is 32-bit, while this rendering path runs inside 64-bit `NvRemixBridge.exe`.
- LumeniteFX supplies estimated/optical-flow motion vectors, not engine-native GTA IV motion vectors.
- DLSS 5 Neural Rendering is substantially more expensive than DLAA alone in this stack.
- The ReShade input patch replaces a **global Vulkan ReShade DLL** under `C:\ProgramData\ReShade`. Restore the original DLL before using software where a custom global graphics layer is inappropriate, especially anti-cheat titles.
- DFC and `nvngx_dlssnr.dll` are not redistributed here.
- The project intentionally pins versions instead of automatically following latest releases.

## Repository layout

```text
install/                         Working installation / backup scripts
config/                          Known-good configuration fragments
manifests/versions.json          Pinned versions, URLs and hashes
input/                           Instructions for user-supplied files
docs/                            Architecture, install, verification and troubleshooting
tools/reshade-bbridge-input/     ReShade 6.8.0 cross-process input patch
tools/debug/bridge-input-poc/    Original transport proof-of-concept source
```

## License

Original scripts, patching glue and documentation in this repository are licensed under the MIT License unless a file says otherwise.

Third-party projects, source code and binaries keep their original licenses. This repository does not relicense them.
