# Third-party components and redistribution policy

This repository is an integration project. It does not claim ownership of the upstream projects or proprietary runtimes it orchestrates.

## Credits and upstream projects

- **GTA IV / Rockstar Games** — target game: https://www.rockstargames.com/games/IV
- **FusionFix** — ThirteenAG and contributors: https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix
- **b-bridge** — gutbash and contributors: https://github.com/gutbash/b-bridge
- **DXVK** — doitsujin and contributors: https://github.com/doitsujin/dxvk
- **ReShade** — Patrick Mours / crosire and contributors: https://github.com/crosire/reshade
- **DLSS5-Feeder** — jlrouzies-fr and contributors: https://github.com/jlrouzies-fr/DLSS5-Feeder
- **LumeniteFX** — umar-afzaal and contributors: https://github.com/umar-afzaal/LumeniteFX
- **NVIDIA NGX / DLSS** — NVIDIA: https://developer.nvidia.com/rtx/dlss
- **RankFTW/rhi-repo** — source used by the installers for the pinned `nvngx_dlss.dll` 310.9.1 package and `nvngx_dlssnr.dll` 310.8.0-RTX40 package: https://github.com/RankFTW/rhi-repo
- **DLSS5 Autopilot** — Kizzuwatnaa and contributors: https://github.com/Kizzuwatnaa/DLSS5-Autopilot. Its GPU/runtime compatibility research is useful for distinguishing the RTX50, RTX40 and SF NR variants.

See `manifests/versions.json` for exact versions, commits, hashes and package URLs.

## What this repository contains

The repository contains:

- original installation/orchestration scripts;
- original documentation;
- small configuration templates;
- source transforms and validation scripts for the project's temporal synchronization and startup-stabilization integration;
- a patching script that applies this project's ReShade 6.8.0 cross-process-input changes to upstream ReShade source;
- the original debug proof-of-concept ReShade input add-on source.

In historical source/checkpoint names, the temporal-synchronization work is called `A3-S2`, the startup-stabilization work is called `A3-S5`, and the project integration namespace is called `M3K`. Those are engineering identifiers, not separate user-facing modules.

## What this repository does not bundle

The Git repository itself does not commit:

- GTA IV game files;
- FusionFix binaries;
- b-bridge release binaries;
- ReShade binaries/source snapshots;
- DLSS5-Feeder binaries;
- LumeniteFX source snapshots;
- NVIDIA NGX runtime DLLs.

Instead, the installers fetch pinned upstream packages at install time and verify hashes where available.

## NVIDIA runtime packages

The current normal install flow automatically fetches both required NGX runtime packages:

```text
nvngx_dlss.dll 310.9.1
nvngx_dlssnr.dll 310.8.0-RTX40
```

The NR package is not stored in this repository. `Install-DLSS-Full.bat` downloads it from the pinned RankFTW/rhi-repo release and verifies both the archive SHA256 and the extracted DLL SHA256.

Current tested NR runtime:

```text
package: nvngx_dlssnr_310.8.0-RTX40.zip
package SHA256: 46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F
DLL SHA256:     4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

This is the RTX 40/50-compatible community build used by the project on RTX 4070 Ti SUPER. It is not the stock RTX50-only FP8 build.

The current project no longer uses or requires Deep Fried Chicken.

Nothing in this repository grants redistribution rights for third-party binaries. Check and follow the upstream licences/terms before redistributing files outside the install-time fetching model used here.

## Trademark / affiliation note

Grand Theft Auto, Rockstar Games, NVIDIA, GeForce, RTX, DLSS and other product names are trademarks of their respective owners. This is an independent community project and is not affiliated with, endorsed by, or sponsored by Rockstar Games, NVIDIA, or the upstream projects listed above.
