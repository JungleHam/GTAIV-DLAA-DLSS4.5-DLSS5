# GTA IV DLSS Full module

This module upgrades the project's working **DLAA** installation to the hardware-validated
full DLSS Super Resolution path without enabling Neural Rendering.

Install order:

```text
FusionFix -> DLAA -> DLSS Full -> optional Neural Rendering
```

The DLSS Full module uses the accepted temporal architecture from the A3-S2 checkpoint
and the A3-S5 automatic startup-prime fix. It does **not** add ray tracing or path tracing.

## What it installs

The installer builds the frozen source checkpoint locally, runs the existing build/test
gates, and then installs:

```text
A3-S2 coherent-jitter b-bridge client d3d9.dll
A3-S5 DLSS5-Feeder add-on
S2.7 stable m3k-nvngx.dll shim
m3k-nr.ini with Mode=0 (NR disabled)
```

The hardware-validated CI reference SHA256 values are:

```text
6DD40F145A5D503624E3E05ECF0ADBAA094CF83B24278C0BB333318E3C52A912  d3d9.dll
C73D8D54271F55F8931F00D62A4CDF605118BEA71D7C6BEE0B61D0CA7C1CCE4B  dlss5-feed.addon64
A2E4BEDACE8D99BC60B5D18E958BD7E98F8887FF40EC45A8674B892E2D1FCBBC  m3k-nvngx.dll
```

A local MSVC build may not be byte-identical to CI because compiler/toolchain revisions can
change PE output. The installer therefore prints reference-hash matches when they occur,
but its correctness gates are the exact frozen source revisions, patch validation, successful
compilation and the existing CPU contract tests.

The frozen project checkpoint used for the build is:

```text
57a8bd2ede8d7b4b721b1981bc0e8a7e6cbe084f
```

Pinned upstream b-bridge source:

```text
1dad5e6d4dcf8647e354aa9a87f611256fb61142
```

## Why the 1485x835 startup prime exists

Cold-start testing found a reproducible vibration in low-resolution SR modes. Generic
feature rebuilds, history resets and profile changes did not cure it. A narrow absolute
source-resolution band did.

Hardware results:

```text
1472x828  -> vibration remains
1478x832  -> fixed
1485x835  -> fixed
1493x840  -> vibration remains
```

The successful resolution was also independent of presenter resolution: the same
~832-835p source band fixed the session at both 1920x1080 and 2560x1440 output.

The production candidate therefore starts at **1485x835**, uses the supported Quality
NGX contract, waits for **180 successful SR frames with the exact A3-S2 synchronized
jitter handoff active**, then automatically releases to the user's saved SR profile.
Temporal history is reset at the transition.

## Profiles

`SRProfile` in `.trex/m3k-nr.ini` selects the saved mode:

| Value | Mode |
|---:|---|
| 1 | Custom Ultra Quality (77%) |
| 2 | Quality |
| 3 | Balanced |
| 4 | Performance |
| 5 | Ultra Performance |

The installer defaults to **Quality**.

## Requirements

Start from this repository's working DLAA installation. GTA IV and `NvRemixBridge.exe`
must be closed.

The local reproducible build requires:

- Git for Windows
- Python 3 in `PATH`
- Visual Studio 2022 Build Tools with Desktop development with C++ / MSVC x86+x64 tools
- Windows SDK
- Internet access for pinned source dependencies

The installer creates a temporary Python virtual environment for the pinned Meson/Ninja
build tools and removes its temporary build directory afterward.

## Installation

Copy:

```text
install/Install-DLSS-Full.bat
```

beside `GTAIV.exe` and run it.

The installer:

1. verifies the existing DLAA/b-bridge baseline,
2. checks out the exact frozen project and b-bridge revisions,
3. builds A3-S5 and the A3-S2 x86 b-bridge client,
4. runs the existing source/build/CPU verification gates,
5. creates a rollback backup,
6. installs the three runtime binaries,
7. writes `Mode=0`, `SRProof=1`, synchronized jitter and startup-prime configuration,
8. installs `DLSS-Full-Control.bat` in the game directory.

Use `DLSS-Full-Control.bat` to choose the saved SR mode and launch GTA with `1485x835`
written before process start. That launcher is the recommended path because it guarantees
the same cold-start condition used for hardware validation.

## Verification

In `.trex/dlss5-feed.log`, a successful cold launch should include evidence equivalent to:

```text
M3K-A3-S5: STARTUP PRIME armed 1485x835
M3K-SR-LIVE: STARTUP PRIME: Quality contract ... true-source=1485x835 ACCEPTED
M3K-A3-S5: prime synchronized to A3-S2 jitter ... at 1485x835
M3K-A3-S5: STARTUP PRIME COMPLETE after 180 synchronized SR frames
M3K-SR-LIVE: ACTIVE <saved mode> ... -> <presenter resolution>
```

The bridge log should show the jitter epoch changing from the 1485x835 prime to the final
source resolution while retaining A3-S2 draw-boundary synchronization.

## Rollback

The installer creates `_DLSS_FULL_PREINSTALL_BACKUP_<timestamp>` beside `GTAIV.exe`.
Close GTA IV and `NvRemixBridge.exe`, then restore the saved files from that folder if
needed.

Neural Rendering is intentionally disabled here (`Mode=0`) so it remains a separate
optional module after DLSS Full.
