# Troubleshooting

## Installer fails

Use the current `GTAIV-DLSS-Setup.exe`. The installer now surfaces the exact inner error message and automatically rolls back a failed DLAA foundation install when possible.

If an old failed attempt left a partial `.trex` or `d3d9Hooked.dll`, the current installer detects the newest `_DLAA_PREINSTALL_BACKUP_*` folder and restores the clean FusionFix baseline before retrying.

## ReShade 6.8.0 exits with code 1

Make sure you selected the exact **ReShade 6.8.0 Full Add-On Support** setup EXE.

Expected SHA256:

```text
AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445
```

The current installer avoids launching ReShade a second time after the Vulkan layer has already been installed.

## Home does not open ReShade

Check:

```text
GTAIV\.trex\ReShade.log
GTAIV\.trex\bridge.conf
```

The bridge config should contain:

```ini
client.DirectInput.forward.mousePolicy = 3
client.DirectInput.forward.keyboardPolicy = 3
```

The patched global ReShade DLL is expected at:

```text
C:\ProgramData\ReShade\ReShade64.dll
```

## DLSS controls

Open:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

Full DLSS starts with:

```text
DLSS profile: Quality
Neural Rendering: OFF
```

Available SR profiles include Ultra Quality 77%, Quality, Balanced, Performance and Ultra Performance.

## Neural Rendering does not start

Check:

```text
GTAIV\.trex\m3k\m3k-nvngx.dll
GTAIV\.trex\m3k\nvngx_dlssnr.dll
GTAIV\.trex\m3k-nr.ini
GTAIV\.trex\dlss5-feed.log
```

Expected NR DLL hashes:

RTX 40 compatibility:

```text
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

RTX 50 NVIDIA-signed:

```text
E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

The RTX 50 DLL must also retain a valid NVIDIA signature.

## Startup vibration

The current Full DLSS configuration uses automatic startup stabilization:

```text
1485x835
180 synchronized frames
then the saved DLSS quality profile
```

If startup settings are damaged, use the installed `DLSS-Full-Control.bat` repair action.

## Need DLSS without Neural Rendering

Leave **Neural Rendering** unchecked in the GTA IV DLSS ReShade panel. Super Resolution remains active.

## Need to remove the project

Run `GTAIV-DLSS-Setup.exe` again and choose:

- **Remove DLSS Full only** to keep the DLAA foundation;
- **Remove everything from this project** to restore the saved pre-project GTA IV/FusionFix baseline.

FusionFix itself is left installed.
