# Third-party components and redistribution policy

This repository is an integration project. It does not claim ownership of GTA IV, upstream projects, or proprietary NVIDIA runtimes.

## Credits and upstream projects

All hyperlinks in this file point to GitHub project pages.

- **FusionFix** — https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix
- **b-bridge** — https://github.com/gutbash/b-bridge
- **DXVK** — https://github.com/doitsujin/dxvk
- **ReShade** — https://github.com/crosire/reshade
- **DLSS5-Feeder** — https://github.com/jlrouzies-fr/DLSS5-Feeder
- **LumeniteFX** — https://github.com/umar-afzaal/LumeniteFX
- **NVIDIA DLSS / NGX** — https://github.com/NVIDIA/DLSS
- **NR package catalog used by the tested integration** — https://github.com/RankFTW/rhi-repo

See `manifests/versions.json` for pinned versions, commits and hashes.

## Repository link policy

The public repository intentionally stores:

- no hyperlink to a non-GitHub site;
- no third-party direct ZIP/EXE/DLL download URL;
- no direct third-party GitHub release-asset URL.

For third-party prerequisites, documentation links to a GitHub project/release-listing page and explains what the user should click. The user obtains the file themselves, keeps it beside the project setup EXE, and the installer validates/installs/extracts it locally. Users are not expected to manually install or extract prerequisites.

## Packaging policy

The project runtime payload may contain project-authored binaries and third-party components whose licences permit redistribution, with required notices/licences included.

The following remain **user supplied** and are installed/extracted by our setup rather than manually by the user:

- FusionFix 5.0.1 ZIP when FusionFix is not already installed;
- official ReShade 6.8.0 full add-on-support setup;
- official pinned LumeniteFX ZIP;
- the GPU-appropriate Neural Rendering ZIP.

### ReShade

ReShade's GitHub repository does not publish the official setup EXE as a GitHub Release. The installer therefore opens only <https://github.com/crosire/reshade> and tells the user to use the project website shown by GitHub's **About** box, then choose the official **ReShade 6.8.0 with full add-on support** download.

Our setup validates the selected EXE, invokes the official installer for the Vulkan bridge renderer, then applies the project's own b-bridge input-patched ReShade build while preserving the official DLL for restoration on uninstall.

### LumeniteFX

The project does not mirror LumeniteFX. Users open the exact pinned source tree on GitHub:

https://github.com/umar-afzaal/LumeniteFX/tree/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9

They use **Code → Download ZIP**, then select that local ZIP. The installer verifies SHA256 before extracting the files required by this integration.

### NVIDIA DLSS Super Resolution / DLAA runtime

The normal `nvngx_dlss.dll` 310.9.1 is sourced from:

https://github.com/NVIDIA/DLSS

The cleaned project runtime build takes the pinned DLL from NVIDIA's repository and records the expected SHA256 in `manifests/versions.json`.

### Neural Rendering runtime

The project does not host, mirror, or store a direct asset link for the NR runtime. Users start at:

https://github.com/RankFTW/rhi-repo

The installer explicitly tells layman users to verify that the repository is **RankFTW/rhi-repo**, click **Releases** in the right sidebar, and move through older release pages with **Next** until the pinned 310.8.0 release appears. The exact number of pages can change as newer releases are added. Setup auto-detects the supported GPU series and gives the corresponding exact release/tag and ZIP filename.

RTX 40 Series:

```text
Find a release: dlssnr-310.8.0-RTX40
Asset name:    nvngx_dlssnr_310.8.0-RTX40.zip
ZIP SHA256:    46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F
DLL SHA256:    4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

RTX 50 Series:

```text
Find a release: dlssnr-310.8.0
Asset name:    nvngx_dlssnr_310.8.0.zip
ZIP SHA256:    388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC
DLL SHA256:    E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

The RTX 40 variant is the project-tested modded compatibility DLL. The RTX 50 variant must also have a valid NVIDIA Authenticode signature.

## Repository contents

The Git repository contains project-authored orchestration, patches, configuration, documentation, validation scripts and source transforms. It does not commit GTA IV files, FusionFix binaries, downloaded ReShade installers, LumeniteFX snapshots, or Neural Rendering runtime DLLs.

Grand Theft Auto, Rockstar Games, NVIDIA, GeForce, RTX, DLSS and other product names are trademarks of their respective owners. This is an independent community project and is not affiliated with, endorsed by, or sponsored by Rockstar Games, NVIDIA, or the upstream projects listed above.
