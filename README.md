# GTA IV — DLAA + DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering

A version-pinned GTA IV integration for **real NVIDIA NGX DLAA**, **DLSS 4.5 Super Resolution**, and **DLSS 5 Neural Rendering / NGX Feature 18** through the 64-bit b-bridge renderer path.

> **Current tested flow:** FusionFix → DLAA → ReShade input fix → combined DLSS 4.5 SR + DLSS 5 NR module. Neural Rendering is installed by the combined module but is **OFF by default**.

> **Hardware validation:** RTX 4070 Ti SUPER. The A3-S2 temporal path was validated across UQ77 / Quality / Balanced / Performance / Ultra Performance. The A3-S5 `1485×835` startup prime fixed the cold-start vibration and automatically returned to the saved SR profile.

This repository is not a modpack. It contains the integration logic, installers, configuration, validation, and source patches. Third-party components are fetched from pinned upstream releases and hash-checked where practical.

## What works

### DLAA baseline

```text
GTAIV.exe (32-bit)
  -> FusionFix
  -> b-bridge
  -> NvRemixBridge.exe (64-bit)
  -> DXVK / Vulkan
  -> ReShade 6.8.0 x64
  -> LumeniteFX depth + motion guides
  -> DLSS5-Feeder
  -> nvngx_dlss.dll 310.9.1
  -> NGX DLAA
```

### DLSS 4.5 Super Resolution

The combined module upgrades the DLAA baseline to true low-resolution GTA/DXVK rendering followed by DLSS Super Resolution:

```text
GTA IV true low-resolution source
  -> coherent A3-S2 raster/DLSS jitter
  -> Lumenite depth + motion guides
  -> DLSS 4.5 Super Resolution (nvngx_dlss.dll 310.9.1)
  -> presenter / monitor resolution
```

Saved SR profiles:

```text
1  Custom Ultra Quality (77%)
2  Quality
3  Balanced
4  Performance
5  Ultra Performance
```

Cold-start vibration is handled automatically by A3-S5:

```text
1485×835 startup prime
  -> 180 synchronized SR frames with A3-S2 jitter active
  -> automatic switch to the saved SR profile
```

### DLSS 5 Neural Rendering — native M3K path

There is **no Deep Fried Chicken stage in the current stack**.

The combined module installs the tested RTX 40/50-compatible `nvngx_dlssnr.dll` 310.8.0-RTX40 runtime automatically and places it at:

```text
GTAIV\.trex\m3k\nvngx_dlssnr.dll
```

NR execution is intentionally left **OFF** after installation:

```ini
Mode=0
NRPasses=1
```

When enabled:

```text
GTA IV true source color
  -> native NGX Feature 18 / DLSS 5 Neural Rendering
  -> DLSS 4.5 Super Resolution
  -> presenter / monitor resolution
```

The NR and SR stages use the same coherent depth, motion-vector and jitter domain. The tested production configuration uses **one NR pass**.

## Prerequisites

| Step | Requirement |
|---|---|
| Base game | GTA IV: Complete Edition / a working PC installation containing `GTAIV.exe` |
| Step 1 | FusionFix 5.0.1 |
| Steps 2–4 | NVIDIA RTX GPU, suitable NVIDIA driver, internet access |
| Steps 3–4 | Git for Windows |
| Steps 3–4 | Python 3 in `PATH` |
| Steps 3–4 | Visual Studio 2022 Build Tools with **Desktop development with C++**, x86+x64 MSVC tools, and a Windows SDK |
| Step 2 / Step 3 install | Administrator permission for the global ReShade Vulkan layer |
| DLSS 5 NR | The bundled tested NR runtime targets RTX 40/50; direct hardware validation for this project is RTX 4070 Ti SUPER |

### Driver notes

`nvngx_dlss.dll` 310.9.1 reports a minimum NVIDIA driver of **512.15**.

The tested `nvngx_dlssnr.dll` 310.8.0-RTX40 runtime reports a minimum driver of **615.00**. If you only use DLAA/SR with NR OFF, the NR driver requirement does not matter. If you turn NR ON, use **615.00 or newer**.

## No “bring your own” files are required

The current normal install flow does **not** require a DFC archive or a manually downloaded NR DLL.

The installers fetch or build the required components themselves, including:

```text
b-bridge
ReShade 6.8.0 Full Add-On Support
DLSS5-Feeder 0.15.1
LumeniteFX
nvngx_dlss.dll 310.9.1
nvngx_dlssnr.dll 310.8.0-RTX40
```

The NR package is fetched from the pinned RankFTW/rhi-repo release and verified by SHA256 before installation.

# Installation overview

---

## STEP 1 — Install FusionFix

Install **FusionFix 5.0.1** into a clean GTA IV installation.

Launch GTA IV once and verify FusionFix works normally. Close the game completely afterward.

The DLAA installer expects this clean baseline and will reject an existing `.trex`/b-bridge install.

---

## STEP 2 — Install DLAA

Copy:

```text
install/Install-DLAA.bat
```

beside `GTAIV.exe` and run it.

This creates the known-good 64-bit b-bridge/ReShade/Feeder DLAA baseline. It installs `nvngx_dlss.dll` 310.9.1 and deliberately does **not** enable Neural Rendering yet.

Launch GTA IV once after Step 2 and confirm the DLAA baseline works before continuing.

Read [`docs/DLAA.md`](docs/DLAA.md).

---

## STEP 3 — Install & verify the ReShade b-bridge input fix

Open:

```text
tools/reshade-bbridge-input/
```

1. Double-click **`BUILD.bat`** and wait for `BUILD SUCCESS - PATCH MARKER VERIFIED`.
2. Close that window.
3. **Right-click `INSTALL.bat` → Run as administrator.**
4. Paste or drag the GTA IV folder containing `GTAIV.exe` into the installer.
5. Launch GTA IV.
6. Press **Home**.

Step 3 is complete only when the ReShade overlay opens **and accepts mouse/keyboard input**.

If Home does nothing, stop and troubleshoot before Step 4.

The patch makes the existing Feeder UI usable through b-bridge; it is not an NR provider itself.

Read [`docs/RESHade-INPUT-PATCH.md`](docs/RESHade-INPUT-PATCH.md).

---

## STEP 4 — Install DLSS 4.5 SR + DLSS 5 NR

Copy:

```text
install/Install-DLSS-Full.bat
```

beside `GTAIV.exe` and run it.

The combined installer:

- builds the frozen A3-S5 Feeder chain;
- builds the accepted A3-S2 coherent-jitter b-bridge client;
- keeps `nvngx_dlss.dll` 310.9.1 as the DLSS 4.5 SR/DLAA runtime;
- automatically downloads and verifies `nvngx_dlssnr.dll` 310.8.0-RTX40;
- installs the NR runtime to `.trex\m3k\`;
- enables the `1485×835` / 180-frame startup prime;
- installs `DLSS-Full-Control.bat`;
- leaves **Neural Rendering OFF by default** (`Mode=0`).

Read [`docs/DLSS-FULL.md`](docs/DLSS-FULL.md).

### Turn DLSS 5 Neural Rendering ON

Close GTA IV, then run:

```text
DLSS-Full-Control.bat
```

Choose:

```text
N  Turn NR ON
```

That writes:

```ini
Mode=2
NRPasses=1
```

Then choose `L` to launch GTA IV through the recommended primed path.

### Turn Neural Rendering OFF

Close GTA IV, run `DLSS-Full-Control.bat`, and choose:

```text
O  Turn NR OFF
```

That restores:

```ini
Mode=0
```

DLSS 4.5 Super Resolution remains active; only the native Feature 18 stage is disabled.

You can also change the saved SR profile from the same control helper.

## DLSS model / preset selector

With the Step 3 ReShade input fix installed:

```text
Home -> Add-ons -> DLSS 5 Feed -> DLSS render preset -> Preset
```

Recommended starting point: **K**. J is the modern alternative if K leaves visible ghosting. E/F are legacy troubleshooting options rather than a simple quality ladder.

Changing the model/preset rebuilds the DLSS feature and may briefly hitch.

## Verification

Main runtime log:

```text
GTAIV\.trex\dlss5-feed.log
```

DLAA evidence includes:

```text
DLSS5_MV_PROVIDER=3
feature ready: ... DLAA
```

DLSS 4.5 SR / startup-prime evidence includes:

```text
M3K-A3-S5: STARTUP PRIME armed 1485x835
M3K-A3-S5: STARTUP PRIME COMPLETE after 180 synchronized SR frames
M3K-SR-LIVE: ACTIVE <saved mode> ...
```

Native NR evidence when `Mode=2` includes successful Feature 18 creation/evaluation and the native NR → SR path. Earlier hardware validation produced logs such as:

```text
M3K-A0: DLSS NR runtime found
M3K-A0: feature 18 creation SUCCESS
M3K-A1: feature 18 evaluation SUCCESS
M3K-A2-S2.6: NR18 -> DLAA running ...
```

See [`docs/VERIFY.md`](docs/VERIFY.md).

## Known-good pinned stack

| Component | Current project baseline |
|---|---|
| FusionFix | 5.0.1 |
| b-bridge base | 0.1.0 / pinned source `1dad5e6d4dcf8647e354aa9a87f611256fb61142` |
| ReShade | 6.8.0 Full Add-On Support + b-bridge input patch |
| DLSS5-Feeder upstream | 0.15.1 |
| LumeniteFX | `f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9` |
| DLSS 4.5 SR / DLAA runtime | `nvngx_dlss.dll` 310.9.1 |
| DLSS 5 NR runtime | `nvngx_dlssnr.dll` 310.8.0-RTX40 |
| Temporal bridge | A3-S2 coherent draw-boundary jitter |
| Combined Feeder | A3-S5 automatic startup prime |
| Frozen project checkpoint | `57a8bd2ede8d7b4b721b1981bc0e8a7e6cbe084f` |
| NR default | OFF (`Mode=0`) |
| NR enabled | `Mode=2`, `NRPasses=1` |

Exact package URLs, hashes and source commits are in [`manifests/versions.json`](manifests/versions.json).

## Important limitations

- GTA IV is 32-bit while the modern NGX/ReShade path runs inside 64-bit `NvRemixBridge.exe`.
- LumeniteFX supplies estimated motion vectors rather than engine-native GTA IV motion vectors.
- The combined module currently relies on the hardware-discovered `1485×835` startup prime before releasing to the saved SR mode.
- The local MSVC-built A3-S2/A3-S5 PE files may not be byte-identical to the reference CI binaries even when built from the same frozen source; source/build/test gates are authoritative and the known hashes remain hardware-reference hashes.
- DLSS 5 Neural Rendering is significantly more expensive than SR alone on RTX 40 hardware.
- The current automatic NR runtime is the tested RTX 40/50-compatible build; other GPU-generation NR variants are not part of this validated install path.
- The ReShade input patch replaces the global Vulkan ReShade DLL under `C:\ProgramData\ReShade`. Restore the original before using software where a custom global graphics layer is inappropriate, especially anti-cheat titles.
- No ray tracing or path tracing code is part of this project’s DLSS 4.5 SR / DLSS 5 NR path.

## Repository layout

```text
install/                         Current modular installers and control helper
config/                          Baseline configuration fragments
manifests/versions.json          Pinned versions, URLs, hashes and checkpoints
input/                           Notes for local experiments; normal install needs no BYO files
docs/                            Architecture, install, verification and troubleshooting
tools/reshade-bbridge-input/     ReShade 6.8.0 cross-process input patch
tools/debug/bridge-input-poc/    Original input-transport proof of concept
```

## Credits & acknowledgements

- [FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) — ThirteenAG and contributors
- [b-bridge](https://github.com/gutbash/b-bridge) — gutbash and contributors
- [DXVK](https://github.com/doitsujin/dxvk) — doitsujin and contributors
- [ReShade](https://github.com/crosire/reshade) — Patrick Mours / crosire and contributors
- [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) — jlrouzies-fr and contributors
- [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX) — umar-afzaal and contributors
- [NVIDIA](https://developer.nvidia.com/rtx/dlss) — NGX / DLSS technology and runtimes
- [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo) — pinned DLSS SR and RTX40-compatible NR runtime packages
- [DLSS5 Autopilot](https://github.com/Kizzuwatnaa/DLSS5-Autopilot) — compatibility research around DLSS 5 NR GPU/runtime variants
- **Rockstar Games** — Grand Theft Auto IV

See [`docs/THIRD-PARTY.md`](docs/THIRD-PARTY.md).

Grand Theft Auto, Rockstar Games, NVIDIA, GeForce, RTX, DLSS and other product names are trademarks of their respective owners. This is an independent community project and is not affiliated with, endorsed by, or sponsored by Rockstar Games, NVIDIA, or the upstream projects listed above.

## License

Original scripts, patching glue and documentation in this repository are licensed under the MIT License unless a file says otherwise.

Third-party projects, source code and binaries keep their original licenses. This repository does not relicense them.
