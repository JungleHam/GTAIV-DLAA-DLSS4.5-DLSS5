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

## Bring your own / prerequisites

The installers fetch **b-bridge, ReShade 6.8.0, DLSS5-Feeder, LumeniteFX and the pinned `nvngx_dlss.dll` automatically**. You do **not** need to download those manually.

Before starting, provide the following:

| Required for | You need to provide | Link |
|---|---|---|
| Base DLAA install | A working Windows PC with an **NVIDIA RTX GPU**, internet access, administrator rights, and a suitable NVIDIA driver | [NVIDIA drivers](https://www.nvidia.com/en-us/drivers/) |
| Base DLAA install | A legitimate PC installation of **GTA IV** with `GTAIV.exe` present. The reference setup was GTA IV: Complete Edition | [GTA IV: Complete Edition on Steam](https://store.steampowered.com/app/12210/Grand_Theft_Auto_IV_The_Complete_Edition/) |
| Base DLAA install | A **clean, working FusionFix 5.0.1 installation**. Launch the game once and confirm FusionFix works before running this project's installer | [FusionFix v5.0.1](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix/releases/tag/v5.0.1) |
| Base DLAA install | No previous `.trex` / b-bridge attempt in the GTA IV folder. The installer intentionally expects a clean FusionFix baseline | — |
| Interactive ReShade/DFC UI patch | **Git for Windows** | [Git for Windows](https://git-scm.com/install/windows) |
| Interactive ReShade/DFC UI patch | **Python 3** available in `PATH` | [Python for Windows](https://www.python.org/downloads/windows/) |
| Interactive ReShade/DFC UI patch | **Visual Studio 2022 Build Tools** with **Desktop development with C++ / MSVC x64 tools** | [Visual Studio 2022 Build Tools](https://aka.ms/vs/17/release/vs_BuildTools.exe) |
| Optional DLSS 5 Neural Rendering | `Deep-Fried-Chicken-v1.7.4-checkpoint-70-chicken-assist-reliability.7z` | [Deep Fried Chicken community / Discord](https://discord.gg/g2v2XGqvR) |
| Optional DLSS 5 Neural Rendering | The tested **RTX 40-compatible `nvngx_dlssnr.dll` 310.8.0** matching the SHA256 listed in [`input/README.md`](input/README.md) | [DLSS5 Autopilot](https://github.com/Kizzuwatnaa/DLSS5-Autopilot) · [releases](https://github.com/Kizzuwatnaa/DLSS5-Autopilot/releases) |

### About the tested `nvngx_dlssnr.dll`

The `nvngx_dlssnr.dll` used for the successful reference setup was obtained through **DLSS5 Autopilot** and was the **RTX 40-series-compatible community build**, intended for Ada / `sm_89` cards such as the RTX 4070 family. DLSS5 Autopilot identifies this branch as **`310.8.0-RTX40`**.

This matters because the Neural Rendering DLL is architecture-specific. The tested file is **not the stock RTX 50 FP8 build**. Our successful reference machine used an **RTX 4070 Ti SUPER**, and the installer identifies the known-good DLL by SHA256 rather than trusting its filename.

See [`input/README.md`](input/README.md) for the exact hash and placement instructions.

### Driver notes

The pinned `nvngx_dlss.dll` 310.9.1 used for DLAA reports a minimum NVIDIA driver of **512.15**. The tested RTX 40-compatible `nvngx_dlssnr.dll` 310.8.0 used for Neural Rendering reports a minimum driver of **615.00**.

For the optional DLSS 5 path, **615.00 or newer is therefore required by the tested NR DLL**. Neural Rendering compatibility has only been directly confirmed by this project on the tested RTX 4070 Ti SUPER setup, so other RTX generations should be treated as unverified until reported working.

### You do not need to bring

The scripts download or prepare these for you:

```text
b-bridge 0.1.0
ReShade 6.8.0 Full Add-On Support
DLSS5-Feeder 0.15.1
LumeniteFX pinned commit
ReShade shader headers pinned commit
nvngx_dlss.dll 310.9.1
7zr.exe if 7-Zip is not already installed (DFC upgrade only)
```

`curl.exe` is optional; the installers fall back to PowerShell downloads when it is unavailable.

## Installation overview

### 1. Install FusionFix first

Start from a **clean FusionFix 5.0.1** setup. Launch GTA IV once and verify FusionFix itself works.

The project does not redistribute FusionFix. The tested upstream package and hash are recorded in [`manifests/versions.json`](manifests/versions.json).

### 2. Install DLAA

Copy:

```text
install/Install-DLAA.bat
```

into the folder containing `GTAIV.exe`, then **double-click it**.

The installer creates a rollback backup, downloads pinned upstream components, installs ReShade 6.8.0 as the Vulkan layer for `NvRemixBridge.exe`, configures Lumenite as Feeder motion-vector provider 3, and enables Feeder DLAA mode at native work resolution.

Read [`docs/DLAA.md`](docs/DLAA.md) first.

### 3. Recommended: install the interactive ReShade patch

This step no longer requires opening PowerShell, Command Prompt, or an Administrator terminal manually.

Open:

```text
tools/reshade-bbridge-input/
```

Then:

1. **Double-click `BUILD.bat`** and wait until it says `SUCCESS`.
2. Close that window and **double-click `INSTALL.bat`**.
3. The installer asks for your GTA IV folder. **Copy/paste the path or drag the folder into the window**, then press **Enter**.
4. Windows will ask for Administrator permission — click **Yes**. The installer continues automatically with the folder you already selected.

Example:

```text
B:\Games\Steam\steamapps\common\Grand Theft Auto IV\GTAIV
```

The path is requested before elevation so normal Explorer drag-and-drop works. The installer is forgiving if you paste `GTAIV.exe` itself or select the outer `Grand Theft Auto IV` folder; it tries to resolve the correct folder automatically.

This builds ReShade from the exact 6.8.0 source tag, applies the cross-process input patch, backs up the active global ReShade Vulkan DLL and replaces it with the patched build.

See [`docs/RESHade-INPUT-PATCH.md`](docs/RESHade-INPUT-PATCH.md).

#### DLAA model / quality preset selector

After Step 3, launch GTA IV and press **Home**, then open:

```text
Add-ons -> DLSS 5 Feed -> DLSS render preset -> Preset
```

The choices mean:

| Choice | Model | What it does |
|---|---|---|
| **K** | Modern transformer | **Recommended.** NVIDIA's default preset for DLAA / Quality / Balanced. Targets the best image quality, with somewhat higher GPU cost than the older models. |
| **J** | Modern transformer | Similar to K, but NVIDIA notes it may show a little less ghosting at the cost of more flicker. Try it if K leaves visible trails. |
| **Default** | Runtime-selected | Does not force a specific model; the NVIDIA runtime picks its normal default. That choice can vary with runtime/OTA behavior. |
| **E** | Legacy CNN | Deprecated old model. Mainly useful for troubleshooting; in this Feeder setup it can sometimes help with motion/transparency warping around smoke, dust, flames, etc. |
| **F** | Legacy CNN | Another deprecated legacy CNN option. Like E, use it as a fallback if the transformer presets produce visible temporal artifacts. |

There is no simple `E < F < J < K` quality ladder for every scene. **Start with K**, try J for ghosting, and treat E/F as troubleshooting alternatives. Changing the preset briefly rebuilds the DLSS feature, so a small hitch is normal.

This selector changes the **DLAA render model only**. It does **not** enable DLSS Super Resolution Quality/Balanced/Performance; GTA IV still renders at native resolution and DLAA remains a 1:1 anti-aliasing pass.

> **DLAA setup is complete after Step 3.** At this point you can stop here and use GTA IV with DLAA only. Everything below is optional and is only for adding **DLSS 5 Neural Rendering** on top of the working DLAA setup.

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

beside `GTAIV.exe` and **double-click it**.

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
| `nvngx_dlssnr.dll` | 310.8.0 RTX 40-compatible community build (`sm_89`), sourced through DLSS5 Autopilot |

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

## Credits & acknowledgements

Huge thanks to the projects and communities this integration builds on:

- [FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) — ThirteenAG and contributors
- [b-bridge](https://github.com/gutbash/b-bridge) — gutbash and contributors, building on NVIDIA bridge work
- [DXVK](https://github.com/doitsujin/dxvk) — doitsujin and contributors
- [ReShade](https://github.com/crosire/reshade) — Patrick Mours / crosire and contributors
- [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) — jlrouzies-fr and contributors
- [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX) — umar-afzaal and contributors
- **Deep Fried Chicken** — its authors/community for the optional Neural Rendering add-on
- [DLSS5 Autopilot](https://github.com/Kizzuwatnaa/DLSS5-Autopilot) — Kizzuwatnaa and contributors; source of the RTX 40-compatible `nvngx_dlssnr.dll` used in the reference setup
- [NVIDIA](https://developer.nvidia.com/rtx/dlss) — NGX / DLSS technology and runtimes
- [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo) — source used for the pinned `nvngx_dlss.dll` package
- [7-Zip](https://www.7-zip.org/) — Igor Pavlov / 7-Zip project
- **Rockstar Games** — Grand Theft Auto IV

See [`docs/THIRD-PARTY.md`](docs/THIRD-PARTY.md) for the expanded third-party and redistribution notes.

Grand Theft Auto, Rockstar Games, NVIDIA, GeForce, RTX, DLSS and other product names are trademarks of their respective owners. This is an independent community project and is not affiliated with, endorsed by, or sponsored by Rockstar Games, NVIDIA, or the upstream projects listed above.

## License

Original scripts, patching glue and documentation in this repository are licensed under the MIT License unless a file says otherwise.

Third-party projects, source code and binaries keep their original licenses. This repository does not relicense them.
