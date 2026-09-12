# Third-party components and redistribution policy

This repository is an integration project. It does not claim ownership of the upstream projects it orchestrates.

## Credits and upstream projects

This project only exists because of the work done by the following projects and communities:

- **GTA IV / Rockstar Games** — the game this integration targets: https://www.rockstargames.com/games/IV
- **FusionFix** — ThirteenAG and contributors: https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix
- **b-bridge** — gutbash and contributors, derived from NVIDIA bridge work: https://github.com/gutbash/b-bridge
- **DXVK** — doitsujin and contributors: https://github.com/doitsujin/dxvk
- **ReShade** — Patrick Mours / crosire and contributors: https://github.com/crosire/reshade
- **DLSS5-Feeder** — jlrouzies-fr and contributors: https://github.com/jlrouzies-fr/DLSS5-Feeder
- **LumeniteFX** — umar-afzaal and contributors: https://github.com/umar-afzaal/LumeniteFX
- **Deep Fried Chicken** — the DFC authors/community responsible for the neural-rendering ReShade add-on used by the optional path. The tested archive is obtained separately and is not redistributed by this repository.
- **DLSS5 Autopilot** — Kizzuwatnaa and contributors: https://github.com/Kizzuwatnaa/DLSS5-Autopilot. The RTX 40-compatible `nvngx_dlssnr.dll` used by the successful reference test was obtained through this project.
- **NVIDIA NGX / DLSS** — NVIDIA: https://developer.nvidia.com/rtx/dlss
- **RankFTW/rhi-repo** — source used by the installer for the pinned `nvngx_dlss.dll` package: https://github.com/RankFTW/rhi-repo
- **7-Zip** — Igor Pavlov / 7-Zip project; the optional DFC installer may fetch `7zr.exe` when no local 7-Zip installation exists: https://www.7-zip.org/

See `manifests/versions.json` for the exact versions, commits, hashes and download locations used by the tested stack.

## What this repository contains

The repository contains:

- original installation/orchestration scripts;
- original documentation;
- small configuration templates;
- a patching script that applies this project's ReShade 6.8.0 cross-process-input changes to source downloaded from the upstream ReShade repository;
- the source of this project's original debug proof-of-concept ReShade add-on.

## What this repository intentionally does not contain

It does not bundle:

- GTA IV game files;
- FusionFix binaries;
- b-bridge binaries;
- DXVK binaries separately from the upstream b-bridge package;
- ReShade binaries/source snapshots;
- DLSS5-Feeder binaries;
- LumeniteFX source snapshots;
- NVIDIA NGX DLLs;
- Deep Fried Chicken binaries/archive;
- DLSS5 Autopilot binaries.

Installers either fetch pinned upstream releases or require the user to supply the file.

## NVIDIA / DFC files

`nvngx_dlss.dll` is fetched as part of the known-good DLAA setup from the pinned package recorded in the manifest.

The tested `nvngx_dlssnr.dll` and DFC archive are **not** committed to this repository. The optional upgrade identifies them by SHA256.

The reference `nvngx_dlssnr.dll` is the **RTX 40 / Ada (`sm_89`) community build** surfaced by DLSS5 Autopilot, not the stock RTX 50 FP8 build.

Nothing in this repository grants redistribution rights for third-party binaries. Check and follow the upstream licenses/terms before redistributing any of them.

## Trademark / affiliation note

Grand Theft Auto, Rockstar Games, NVIDIA, GeForce, RTX, DLSS and other product names are trademarks of their respective owners. This repository is an independent community project and is not affiliated with, endorsed by, or sponsored by Rockstar Games, NVIDIA, or the upstream projects listed above.
