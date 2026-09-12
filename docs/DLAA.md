# DLAA installation

## Prerequisites

Use GTA IV Complete Edition with a clean, working **FusionFix 5.0.1** installation.

Before running the project installer:

1. launch GTA IV once;
2. verify FusionFix loads normally;
3. close GTA IV completely;
4. make sure no old `.trex` folder or previous b-bridge experiment remains.

The installer is deliberately strict about this clean baseline because its automatic rollback logic assumes it.

## Install

Copy `install/Install-DLAA.bat` into the same folder as `GTAIV.exe` and double-click it.

The BAT contains an embedded PowerShell installer and elevates itself once because ReShade's Vulkan global-layer registration needs Administrator rights.

It downloads only pinned upstream packages and verifies the hashes that are recorded in `manifests/versions.json` where available.

## Resulting important files

```text
GTAIV\
  dinput8.dll                     FusionFix ASI loader
  d3d9.dll                        b-bridge client
  d3d9Hooked.dll                  FusionFix's renderer wrapper, chained by b-bridge
  dxvk.conf
  commandline.txt
  .trex\
    NvRemixBridge.exe
    d3d9vk_x64.dll
    bridge.conf
    ReShade.ini
    ReShadePreset.ini
    dlss5-feed.addon64
    dlss5-feed.cfg
    nvngx_dlss.dll
    reshade-shaders\
      Shaders\
        lumenite_Kernel.fx
        DLSS5_Feed.fx
        ReShade.fxh
        ReShadeUI.fxh
        DrawText.fxh
      Textures\
        lumenite_bluenoise256.png
```

## Known-good configuration

FusionFix:

```ini
[MAIN]
GraphicsAPI=0
Windowed=1
BorderlessWindowed=1

[MISC]
Antialiasing=5

[FRAMELIMIT]
FpsLimitPreset=0
```

`commandline.txt` contains:

```text
-windowed
```

Feeder:

```ini
enabled=1
mode=2
work_resolution=100
```

ReShade preset:

```ini
Techniques=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx
TechniqueSorting=Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx,DLSS5_Feed_Debug@DLSS5_Feed.fx

[DLSS5_Feed.fx]
PreprocessorDefinitions=DLSS5_MV_PROVIDER=3
```

Do not append `\**` to the ReShade shader search paths in this stack; that previously produced invalid-path/shader-loading failures.

## DLAA model / preset selector

After the ReShade b-bridge input patch from **Step 3** of the main README is installed, the existing DLSS5-Feeder model selector becomes fully interactive.

Launch GTA IV and press **Home**, then go to:

```text
Add-ons -> DLSS 5 Feed -> DLSS render preset -> Preset
```

### What each preset means

| Preset | Model type | What it means / when to use it |
|---|---|---|
| **K** | Modern transformer | **Recommended.** NVIDIA defines K as the default preset for DLAA, Quality and Balanced. It targets the best image quality, with somewhat higher GPU cost than older models. Start here. |
| **J** | Modern transformer | Very similar to K. NVIDIA notes that J can show a little less ghosting, but may introduce more flicker. Try it if K leaves visible trails or temporal smearing. |
| **Default** | Runtime-selected | Does not force a specific model. The NVIDIA runtime chooses its default, which may change with runtime/OTA behavior. Use this if you want the runtime's normal policy instead of pinning a model. |
| **E** | Legacy CNN | Deprecated by NVIDIA. Kept mainly as a troubleshooting option. In this Feeder setup, older CNN behavior can sometimes reduce motion/transparency warping around things like smoke, dust or flames. |
| **F** | Legacy CNN | Also a deprecated legacy CNN preset. Treat it like E: not a normal quality upgrade, but another fallback to try if the transformer presets produce motion artifacts. |

There is **no universal quality ladder** where E < F < J < K in every scene. K is the normal recommendation; J is the modern alternative; E/F are compatibility/troubleshooting choices.

Changing the preset in the Home menu causes Feeder to rebuild the DLSS feature and stores the selected value in `.trex\dlss5-feed.cfg`. A short hitch while the feature rebuilds is normal.

This control changes the **DLAA model/preset only**. It does not turn GTA IV into DLSS Super Resolution Quality/Balanced/Performance; the game still renders at native resolution and the DLSS feature remains DLAA / 1:1.

## What the DLAA installer intentionally does not install

The base install removes/avoids:

- `nvngx_dlssnr.dll`
- Deep Fried Chicken
- RenoDX DLSS5 provider add-ons
- OptiScaler neural consumers

The point is to establish a known-good DLAA baseline before adding Neural Rendering.

## After installation

Launch GTA IV normally. The first launch may spend time compiling shaders.

Then inspect `.trex\dlss5-feed.log`. See `VERIFY.md`.
