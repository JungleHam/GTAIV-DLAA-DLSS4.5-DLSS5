# DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering

## What Full DLSS adds

Full mode builds on the DLAA foundation and enables Super Resolution profiles plus optional Neural Rendering.

```text
GTA IV internal image
 -> DLSS 5 Neural Rendering (optional)
 -> DLSS 4.5 Super Resolution / DLAA
 -> display/output resolution
```

## Do not manually install prerequisites

Keep `GTAIV-DLSS-Setup.exe` and every downloaded prerequisite in one temporary setup-files folder. Leave the downloaded ZIP/EXE files untouched. Setup validates and installs/extracts them itself.

See [`PREREQUISITES.md`](PREREQUISITES.md) for the beginner click guide.

## Neural Rendering package: exact GitHub route

Start at:

<https://github.com/RankFTW/rhi-repo>

Make sure the repository says **`RankFTW / rhi-repo`**, not the separate `RankFTW / RHI` project.

1. On the right side of the repository page click **Releases**.
2. The required 310.8.0 releases are older and may be several pages down.
3. Scroll to the bottom of the Releases page and click **Next** to show older releases.
4. Keep clicking **Next** until you find the exact release/tag for your GPU. This may take a couple of pages and can change as new releases are added.
5. You can also try GitHub's **Find a release** box with the exact tag below.
6. Open the release, expand **Assets**, download the named ZIP, and put it beside our setup EXE.
7. **Do not extract the ZIP.** Setup does that.

| GPU | Exact release/tag | ZIP under Assets | Expected DLL SHA256 |
|---|---|---|---|
| **RTX 40** | `dlssnr-310.8.0-RTX40` | `nvngx_dlssnr_310.8.0-RTX40.zip` | `4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05` |
| **RTX 50** | `dlssnr-310.8.0` | `nvngx_dlssnr_310.8.0.zip` | `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E` |

RTX 40 archive SHA256:

```text
46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F
```

RTX 50 archive SHA256:

```text
388C0A7912E15EC911B9C9E11A692142B11FE387DDF2B637D8C358138FFFB3AC
```

The RTX 40 file is the project-tested **modded compatibility DLL**. RTX 50 uses the plain 310.8.0 NVIDIA-signed runtime; do not choose the `-RTX40` package for an RTX 50 card.

## Install

Run `GTAIV-DLSS-Setup.exe` and choose **Install / repair Full DLSS**.

- Setup detects RTX 40 vs RTX 50 and repeats the exact package instructions.
- If FusionFix is missing, setup can install the user-downloaded FusionFix ZIP first; you then launch GTA IV once and rerun setup.
- If the DLAA foundation is missing, setup asks for ReShade and LumeniteFX and installs that foundation automatically.
- Setup takes the downloaded NR ZIP directly; no manual extraction is needed.
- The normal `nvngx_dlss.dll` 310.9.1 used for DLSS 4.5 / DLAA comes from the project runtime and is sourced from [NVIDIA/DLSS](https://github.com/NVIDIA/DLSS).

## Defaults

```text
DLSS profile: Quality
Neural Rendering: OFF on the first completed Full DLSS launch
NR passes when enabled: 1
startup stabilization: 1485×835 for 180 valid synchronized frames
```

**Neural Rendering is installed but deliberately starts OFF.** The first Full DLSS launch therefore validates the DLSS 4.5 Super Resolution path without NR. Enable NR later from the ReShade Add-ons panel if wanted.

Keep GTA IV's normal display resolution set to your monitor's native resolution. The project manages the internal render resolution independently.

## In-game controls

Press **Home** and open:

```text
Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

Available modes include DLAA Native, Ultra Quality 77%, Quality, Balanced, Performance and Ultra Performance. Neural Rendering and NR pass count are controlled from the same panel.

## Rollback

Run setup and choose **Remove DLSS Full only** to restore the preserved DLAA baseline. The user-supplied NR DLL is removed with Full DLSS; the DLAA/ReShade/Lumenite foundation remains.
