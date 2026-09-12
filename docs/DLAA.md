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

Copy `install/Install-DLAA.bat` into the same folder as `GTAIV.exe` and run it.

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
