# Prerequisites and pinned packages

Normal users only need the main installer. Everything hosted on GitHub is downloaded automatically.

## Manual prerequisite

### ReShade 6.8.0 Full Add-On Support

Start at:

https://github.com/crosire/reshade

The required setup EXE is not published as a GitHub Release.

1. Open the ReShade GitHub repository.
2. Use the official project website shown in the GitHub **About** box.
3. Download **ReShade 6.8.0 with full add-on support**.
4. Select that EXE when GTA IV DLSS Setup asks for it.
5. Do not run ReShade yourself.

Expected setup SHA256:

```text
AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445
```

## Automatic downloads

### FusionFix 5.0.1

Source:

https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix

Expected ZIP SHA256:

```text
3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41
```

If FusionFix is newly installed, launch GTA IV once to the main menu, close it, and rerun setup.

### LumeniteFX

Source:

https://github.com/umar-afzaal/LumeniteFX

Pinned commit:

```text
f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9
```

Expected GitHub API archive SHA256:

```text
572FEFB20D466AFE50998E16996B4833BEC675264485C99FE768A2337636E756
```

### DLSS 5 Neural Rendering — Full DLSS only

Source:

https://github.com/RankFTW/rhi-repo

RTX 40:

```text
tag:   dlssnr-310.8.0-RTX40
asset: nvngx_dlssnr_310.8.0-RTX40.zip
ZIP:   46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F
DLL:   4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

RTX 50:

```text
tag:   dlssnr-310.8.0
asset: nvngx_dlssnr_310.8.0.zip
ZIP:   388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC
DLL:   E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

The RTX 50 DLL must retain a valid NVIDIA Authenticode signature.

## I brought my own

On the Full DLSS GPU page, check **I brought my own** to use an existing `nvngx_dlssnr.dll`.

The installer does not trust the file blindly. It still checks the exact GPU-specific SHA256 above, and on RTX 50 also verifies the NVIDIA signature.

If the box is left unchecked, setup downloads the matching package automatically.

## Other components

Users do not need to locate b-bridge, DXVK/presenter files, DLSS5-Feeder, ReShade headers, the standard DLSS SR/DLAA runtime, or project-built DLLs. They are handled by the project runtime.
