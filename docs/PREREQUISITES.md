# Prerequisites

The installer now downloads every GitHub-hosted prerequisite automatically.

## Normal user flow

1. Run `GTAIV-DLSS-Setup.exe`.
2. Select the GTA IV folder and choose DLAA or Full DLSS.
3. Setup automatically resolves, downloads and verifies:
   - [FusionFix 5.0.1](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix), if missing;
   - pinned [LumeniteFX](https://github.com/umar-afzaal/LumeniteFX);
   - the correct RTX 40/50 Neural Rendering package from [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo) for Full DLSS;
   - this project's runtime and ReShade input patch.
4. If FusionFix was just installed, launch GTA IV once to the main menu, close it, then run setup again.
5. If a fresh DLAA foundation is required, provide the official ReShade 6.8.0 Full Add-On installer.

ReShade is the only manual prerequisite in the normal flow.

## ReShade 6.8.0 Full Add-On Support

Start at [crosire/reshade](https://github.com/crosire/reshade).

ReShade does not publish the required installer EXE as a GitHub Release.

1. Open the ReShade GitHub repository.
2. In the **About** box, open the official project website shown there.
3. Find **ReShade 6.8.0 with full add-on support**.
4. Download that installer, not the normal build.
5. Select the EXE in GTA IV DLSS Setup.
6. Do not run ReShade yourself; setup runs it against the correct bridge target.

Expected SHA256:

```text
AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445
```

## Automatic GitHub downloads

### FusionFix 5.0.1

Source: [ThirteenAG/GTAIV.EFLC.FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix)

Expected release ZIP SHA256:

```text
3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41
```

### LumeniteFX

Source: [umar-afzaal/LumeniteFX](https://github.com/umar-afzaal/LumeniteFX)

Pinned commit:

```text
f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9
```

The installer downloads the pinned commit through the GitHub API. Expected API-archive SHA256:

```text
572FEFB20D466AFE50998E16996B4833BEC675264485C99FE768A2337636E756
```

### DLSS Neural Rendering — Full DLSS only

Source: [RankFTW/rhi-repo](https://github.com/RankFTW/rhi-repo)

The installer detects RTX 40/50 in the wizard and automatically resolves the exact package.

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

The RTX 50 DLL must also retain a valid NVIDIA Authenticode signature.

## Other components

Users do not need to locate b-bridge, DXVK/presenter files, DLSS5-Feeder, ReShade headers, the standard DLSS SR/DLAA runtime, or project-built DLLs. Setup handles those through the project runtime.
