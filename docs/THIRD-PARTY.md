# Third-party components and redistribution policy

This repository is an integration project. It does not claim ownership of the upstream projects it orchestrates.

## Upstream projects used by the tested stack

- **FusionFix** — ThirteenAG / FusionFix contributors
- **b-bridge** — gutbash / NVIDIA bridge-derived code
- **ReShade** — crosire / Patrick Mours and contributors
- **DLSS5-Feeder** — jlrouzies-fr and contributors
- **LumeniteFX** — umar-afzaal and contributors
- **NVIDIA NGX / DLSS runtimes** — NVIDIA
- **Deep Fried Chicken** — its respective author(s)

See `manifests/versions.json` for the exact versions and source URLs used by this project.

## What this repository contains

The repository contains:

- original installation/orchestration scripts;
- original documentation;
- small configuration templates;
- a patching script that applies the project's ReShade 6.8.0 cross-process-input changes to source downloaded from the upstream ReShade repository;
- the source of the project's original debug proof-of-concept ReShade add-on.

## What this repository intentionally does not contain

It does not bundle:

- FusionFix binaries;
- b-bridge binaries;
- ReShade binaries/source snapshots;
- DLSS5-Feeder binaries;
- LumeniteFX source snapshots;
- NVIDIA NGX DLLs;
- Deep Fried Chicken binaries/archive.

Installers either fetch pinned upstream releases or require the user to supply the file.

## NVIDIA / DFC files

`nvngx_dlss.dll` is fetched as part of the known-good DLAA setup from the pinned package recorded in the manifest.

The tested `nvngx_dlssnr.dll` and DFC archive are **not** committed to this repository. The optional upgrade identifies them by SHA256.

Nothing in this repository grants redistribution rights for third-party binaries. Check and follow the upstream licenses/terms before redistributing any of them.
