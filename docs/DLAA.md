# DLAA installation

## Purpose

Step 2 creates a clean, known-good DLAA baseline before the ReShade input fix and combined DLSS 4.5 SR + DLSS 5 NR module are added.

## Prerequisites

Use GTA IV Complete Edition with a clean, working **FusionFix 5.0.1** installation.

Before running the project installer:

1. launch GTA IV once;
2. verify FusionFix loads normally;
3. close GTA IV completely;
4. make sure no old `.trex` folder or previous b-bridge experiment remains.

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
  d3d9.dll                        b-bridge client
  d3d9Hooked.dll                  FusionFix renderer wrapper chained by b-bridge
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

Do not append `\**` to the ReShade shader search paths in this stack.

## What Step 2 intentionally does not install

The DLAA baseline does not yet install the native M3K NR runtime or A3-S2/A3-S5 SR path.

In particular, after Step 2 you should not yet have:

```text
.trex\m3k-nr.ini
.trex\m3k\m3k-nvngx.dll
.trex\m3k\nvngx_dlssnr.dll
```

Those arrive automatically in Step 4.

## DLAA model / preset selector

After completing the ReShade b-bridge input patch in Step 3, press Home and open:

```text
Add-ons -> DLSS 5 Feed -> DLSS render preset -> Preset
```

Recommended starting point: **K**.

- **K** — modern transformer; normal recommendation.
- **J** — modern alternative; may trade a little less ghosting for more flicker.
- **Default** — runtime-selected policy.
- **E/F** — legacy CNN troubleshooting choices.

Changing the preset rebuilds the DLSS feature and may briefly hitch.

At this stage GTA IV still renders at native resolution; this selector does not by itself enable Super Resolution.

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
