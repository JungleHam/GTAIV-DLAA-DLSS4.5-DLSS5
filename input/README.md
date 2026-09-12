# User-supplied files

This repository deliberately does **not** redistribute Deep Fried Chicken or `nvngx_dlssnr.dll`.

For the tested DLSS 5 Neural Rendering upgrade, place these files either beside `Upgrade-DLSS5-DFC.bat`, on your Desktop, or in Downloads:

```text
Deep-Fried-Chicken-v1.7.4-checkpoint-70-chicken-assist-reliability.7z
nvngx_dlssnr.dll
```

The installer identifies them by SHA256 rather than by filename.

Known-good hashes:

```text
DFC archive:
91dc4137b1f2d7cdbd7f9eb4de9d33848b59e3af7a747d5d798271ee262eab09

nvngx_dlssnr.dll 310.8.0:
4b8d19bc3eff58a084f5eca7489c921501c203450169fb82ff4f649a4482ba05
```

The tested DFC archive is password protected with:

```text
chicken
```

`nvngx_dlss.dll` does **not** need to be supplied again: the DLSS 5 upgrade verifies and reuses the 310.9.1 DLL installed by `Install-DLAA.bat`.

If your files do not match these hashes, the installer stops instead of silently mixing untested versions.
