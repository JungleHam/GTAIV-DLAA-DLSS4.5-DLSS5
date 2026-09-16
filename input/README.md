# Input / local runtime files

## Normal installation: nothing to bring

The current supported install flow does **not** require any manually downloaded files in this directory.

You do **not** need to supply:

```text
Deep Fried Chicken
nvngx_dlssnr.dll
nvngx_dlss.dll
```

The normal installers fetch the pinned runtime packages automatically and verify their hashes.

## Current automatic runtime sources

DLSS 4.5 SR / DLAA:

```text
nvngx_dlss.dll 310.9.1
https://github.com/RankFTW/rhi-repo/releases/download/dlss-310.9.1/nvngx_dlss_310.9.1.zip
```

DLSS 5 Neural Rendering:

```text
nvngx_dlssnr.dll 310.8.0-RTX40
https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0-RTX40/nvngx_dlssnr_310.8.0-RTX40.zip
```

The combined Step 4 installer verifies:

```text
NR package SHA256:
46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F

Extracted nvngx_dlssnr.dll SHA256:
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

## Why this folder still exists

It is kept only as a convenient ignored location for developers doing local runtime experiments. Files placed here are not consumed by the normal current installer.

Do not commit proprietary/runtime DLLs or archives to the repository.
