# DLAA installation

## Purpose

Step 2 creates a clean, known-good DLAA baseline before the ReShade controls fix and the combined DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering module are added.

## Prerequisites

Use GTA IV Complete Edition with a clean, working **FusionFix 5.0.1** installation.

Before running the project installer:

1. launch GTA IV once;
2. verify FusionFix loads normally;
3. close GTA IV completely;
4. make sure no old `.trex` folder or previous bridge experiment remains.

The installer is deliberately strict because its rollback logic assumes a clean FusionFix baseline.

## Install

Copy:

```text
install/Install-DLAA.bat
```

beside `GTAIV.exe` and run it.

The BAT contains an embedded PowerShell installer and elevates itself because ReShade's global Vulkan-layer registration requires Administrator permission.

It downloads pinned upstream packages and verifies hashes recorded in `manifests/versions.json` where available.

## Resulting important files

```text
GTAIV\
  dinput8.dll                     FusionFix ASI loader
  d3d9.dll                        bridge client
  d3d9Hooked.dll                  FusionFix renderer wrapper chained by the bridge
  dxvk.conf
  commandline.txt
  .trex\
    NvRemixBridge.exe             64-bit renderer process
    d3d9vk_x64.dll
    bridge.conf
    ReShade.ini
    ReShadePreset.ini
    dlss5-feed.addon64
    dlss5-feed.cfg
    nvngx_dlss.dll                310.9.1
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

## Known-good base configuration

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

`commandline.txt`:

```text
-windowed
```

DLSS feeder:

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

Do not append `\**` to the ReShade shader search paths in this stack.

## What Step 2 intentionally does not install

Step 2 is only the **DLAA baseline**. It does not yet add:

- DLSS Super Resolution quality modes;
- the temporal synchronization used by Super Resolution;
- automatic startup stabilization;
- the DLSS 5 Neural Rendering runtime.

Those arrive together in Step 4.

After Step 2 you should therefore not yet have:

```text
.trex\m3k-nr.ini
.trex\m3k\m3k-nvngx.dll
.trex\m3k\nvngx_dlssnr.dll
```

The `m3k` name in those paths is only the project's internal integration namespace.

## DLAA model / preset selector

After completing the **ReShade controls fix** in Step 3, press Home and open:

```text
Add-ons -> DLSS 5 Feed -> DLSS render preset -> Preset
```

Recommended starting point: **K**.

- **K** — modern transformer; normal recommendation.
- **J** — modern alternative; may trade a little less ghosting for more flicker.
- **Default** — runtime-selected policy.
- **E/F** — legacy CNN troubleshooting choices.

Changing the preset rebuilds the DLSS feature and may briefly hitch.

At this stage GTA IV still renders at native/output resolution; this selector does not by itself enable Super Resolution.

## Verify before continuing

Launch GTA IV and inspect:

```text
.trex\dlss5-feed.log
```

Expected evidence includes:

```text
DLSS5_MV_PROVIDER=3
feature ready: <native resolution> DLAA ...
frame ... delivered
```

Only after the DLAA baseline works should you continue to Step 3 and Step 4.
