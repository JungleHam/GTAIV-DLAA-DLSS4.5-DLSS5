# User-supplied files

This repository deliberately does **not** redistribute Deep Fried Chicken or `nvngx_dlssnr.dll`.

For the tested DLSS 5 Neural Rendering upgrade, place these files either beside `Upgrade-DLSS5-DFC.bat`, on your Desktop, or in Downloads:

```text
Deep-Fried-Chicken-v1.7.4-checkpoint-70-chicken-assist-reliability.7z
nvngx_dlssnr.dll
```

## Where to get them

### Deep Fried Chicken

The tested DFC build came from the Deep Fried Chicken community distribution used by DLSS5-Feeder:

- Deep Fried Chicken / community Discord: https://discord.gg/g2v2XGqvR
- DLSS5-Feeder project: https://github.com/jlrouzies-fr/DLSS5-Feeder

The exact tested archive is:

```text
Deep-Fried-Chicken-v1.7.4-checkpoint-70-chicken-assist-reliability.7z
```

### `nvngx_dlssnr.dll`

The tested Neural Rendering DLL was obtained through **DLSS5 Autopilot**:

- Project: https://github.com/Kizzuwatnaa/DLSS5-Autopilot
- Releases: https://github.com/Kizzuwatnaa/DLSS5-Autopilot/releases

The file used by this project was the **RTX 40-series-compatible community build** used by DLSS5 Autopilot for Ada / `sm_89` GPUs. Autopilot identifies this branch as:

```text
310.8.0-RTX40
community build
sm_89
```

That is the build intended for RTX 40-series cards such as the RTX 4070 family. The successful reference setup for this repository used an **RTX 4070 Ti SUPER**.

This is important: do **not** substitute the stock RTX 50 FP8 build and assume it is equivalent. `nvngx_dlssnr.dll` is architecture-specific.

## Known-good hashes

The installer identifies the user-supplied files by SHA256 rather than trusting filenames.

```text
DFC archive:
91dc4137b1f2d7cdbd7f9eb4de9d33848b59e3af7a747d5d798271ee262eab09

nvngx_dlssnr.dll 310.8.0 RTX 40-compatible build:
4b8d19bc3eff58a084f5eca7489c921501c203450169fb82ff4f649a4482ba05
```

The tested DFC archive is password protected with:

```text
chicken
```

`nvngx_dlss.dll` does **not** need to be supplied again: the DLSS 5 upgrade verifies and reuses the 310.9.1 DLL installed by `Install-DLAA.bat`.

If your files do not match these hashes, the installer stops instead of silently mixing untested versions.
