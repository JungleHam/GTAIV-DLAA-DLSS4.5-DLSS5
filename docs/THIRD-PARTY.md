# Third-party components and redistribution policy

This repository is an integration project. It does not claim ownership of GTA IV, upstream projects, or proprietary NVIDIA runtimes.

## Upstream projects

- FusionFix — https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix
- b-bridge — https://github.com/gutbash/b-bridge
- DXVK — https://github.com/doitsujin/dxvk
- ReShade — https://github.com/crosire/reshade
- DLSS5-Feeder — https://github.com/jlrouzies-fr/DLSS5-Feeder
- LumeniteFX — https://github.com/umar-afzaal/LumeniteFX
- NVIDIA DLSS — https://github.com/NVIDIA/DLSS
- NR package catalog — https://github.com/RankFTW/rhi-repo

Pinned versions and hashes are recorded in `manifests/versions.json`.

## Link policy

Repository hyperlinks intentionally point only to GitHub/GitHub-owned hosts.

The repository does not store hard-coded direct third-party ZIP/EXE/DLL release-asset URLs. The installer resolves allowed GitHub release assets through the GitHub API at runtime.

ReShade is the exception to automatic acquisition because the required official setup EXE is not hosted as a GitHub Release. The installer opens the ReShade GitHub project and tells the user to use the official website shown in its GitHub **About** box.

## Runtime packaging

The cleaned project runtime may contain project-built files and third-party components whose licences permit redistribution, with required licence notices included.

The installer automatically obtains and verifies:

- FusionFix 5.0.1 when missing;
- pinned LumeniteFX;
- the GPU-matched Neural Rendering package for RTX 40/50;
- the project's own runtime and ReShade input patch.

A user may alternatively select an already-owned `nvngx_dlssnr.dll` through **I brought my own**. That local DLL is still validated against the pinned GPU-specific hash.

The repository itself does not commit GTA IV files, downloaded ReShade installers, FusionFix binaries, LumeniteFX snapshots, or Neural Rendering runtime DLLs.

## ReShade input patch

The official ReShade Vulkan layer is installed first. The project then replaces the global ReShade DLL with its ReShade 6.8.0 b-bridge input-patched build while preserving the official DLL for restoration.

The patch exists only to make ReShade input work when GTA IV owns the window but ReShade runs in the separate bridge process.

## Independence

Grand Theft Auto, Rockstar Games, NVIDIA, GeForce, RTX, DLSS and other product names are trademarks of their respective owners.

This is an independent community project and is not affiliated with, endorsed by, or sponsored by Rockstar Games, NVIDIA, or the upstream projects listed above.
