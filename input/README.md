# Input / user-supplied prerequisite files

This folder is optional and mostly useful to developers. Normal users should instead make their own simple folder beside the downloaded `GTAIV-DLSS-Setup.exe` and put every prerequisite download there.

Users should **not** install or extract prerequisites themselves. The release installer is designed to validate and handle them.

See [`../docs/PREREQUISITES.md`](../docs/PREREQUISITES.md) for the exact beginner GitHub click paths.

## Possible user-supplied files

FusionFix when missing:

```text
GTAIV.EFLC.FusionFix.zip
SHA256:
3C202398C133392BE985854654F169514E055812CC302EF24E6AA97495975B41
```

Fresh DLAA / Full foundation:

```text
ReShade_Setup_6.8.0_Addon.exe
SHA256:
AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445

LumeniteFX pinned commit ZIP
SHA256:
43220F99FC0FFA0216E01EBD657180F8C9D043C939F760283B896EA257F1B6A2
```

Full DLSS / RTX 40 Neural Rendering:

```text
GitHub repo: RankFTW/rhi-repo
Release/tag: dlssnr-310.8.0-RTX40
Archive: nvngx_dlssnr_310.8.0-RTX40.zip
Archive SHA256:
46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F
DLL SHA256:
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

Full DLSS / RTX 50 Neural Rendering:

```text
GitHub repo: RankFTW/rhi-repo
Release/tag: dlssnr-310.8.0
Archive: nvngx_dlssnr_310.8.0.zip
Archive SHA256:
388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC
DLL SHA256:
E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

The RTX 50 variant must also have a valid NVIDIA Authenticode signature.

Do not commit proprietary/runtime DLLs, downloaded installers, or third-party archives to this repository.
