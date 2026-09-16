# DLSS 4.5 Super Resolution + DLSS 5 Neural Rendering

This is the current combined module installed after the DLAA baseline and ReShade input fix.

```text
FusionFix -> DLAA -> ReShade input fix -> DLSS 4.5 SR + DLSS 5 NR
```

The module installs both Super Resolution and the native M3K Neural Rendering runtime. **NR execution is OFF by default.**

## What it installs

The installer builds the frozen project path and installs:

```text
A3-S2 coherent-jitter b-bridge client d3d9.dll
A3-S5 DLSS5-Feeder add-on
S2.7 m3k-nvngx.dll shim
nvngx_dlssnr.dll 310.8.0-RTX40
m3k-nr.ini
DLSS-Full-Control.bat
```

The existing DLAA runtime remains:

```text
nvngx_dlss.dll 310.9.1
```

This is the project’s DLSS 4.5 SR / DLAA runtime.

## Frozen source checkpoints

Project checkpoint:

```text
57a8bd2ede8d7b4b721b1981bc0e8a7e6cbe084f
```

Pinned b-bridge source:

```text
1dad5e6d4dcf8647e354aa9a87f611256fb61142
```

Hardware-reference hashes:

```text
6DD40F145A5D503624E3E05ECF0ADBAA094CF83B24278C0BB333318E3C52A912  d3d9.dll
C73D8D54271F55F8931F00D62A4CDF605118BEA71D7C6BEE0B61D0CA7C1CCE4B  dlss5-feed.addon64
A2E4BEDACE8D99BC60B5D18E958BD7E98F8887FF40EC45A8674B892E2D1FCBBC  m3k-nvngx.dll
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05  nvngx_dlssnr.dll
```

The locally compiled PE files may differ byte-for-byte with newer MSVC revisions even when built from the exact same frozen source. The source/build/test gates are authoritative; the hashes above identify the hardware-tested reference binaries.

## NR runtime package

The installer downloads the exact pinned package automatically:

```text
https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0-RTX40/nvngx_dlssnr_310.8.0-RTX40.zip
```

Package SHA256:

```text
46124CFAEF532AD5F6DA07494772EA8C1B3E719F934E254385697F38D1289E3F
```

The installer then verifies the DLL itself against:

```text
4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05
```

No manually downloaded DFC archive or NR DLL is required.

## DLSS 4.5 SR profiles

`SRProfile` in `.trex/m3k-nr.ini` selects the saved mode:

| Value | Mode |
|---:|---|
| 1 | Custom Ultra Quality (77%) |
| 2 | Quality |
| 3 | Balanced |
| 4 | Performance |
| 5 | Ultra Performance |

The installer defaults to **Quality**.

## 1485x835 startup prime

Cold-start testing found a narrow source-resolution band that reliably initializes the session without the low-resolution vibration:

```text
1472x828  -> vibration remains
1478x832  -> fixed
1485x835  -> fixed
1493x840  -> vibration remains
```

The final A3-S5 path therefore starts at:

```text
1485x835
```

It waits for **180 successful SR frames while the exact A3-S2 synchronized jitter handoff is active**, then automatically returns to the saved SR profile and resets temporal history.

This startup prime was hardware-validated on the RTX 4070 Ti SUPER and fixed the previously observed cold-start vibration, including Ultra Performance.

## Neural Rendering default state

After installation:

```ini
Mode=0
NRPasses=1
```

The NR runtime is present, but Feature 18 is not executed.

### Turn NR ON

Close GTA IV and run:

```text
DLSS-Full-Control.bat
```

Choose:

```text
N  Turn NR ON
```

The helper writes:

```ini
Mode=2
NRPasses=1
```

The current production path becomes:

```text
true GTA source color
 -> native NGX Feature 18 / DLSS 5 NR
 -> DLSS 4.5 Super Resolution
 -> output
```

### Turn NR OFF

Close GTA IV, run `DLSS-Full-Control.bat`, and choose:

```text
O  Turn NR OFF
```

This writes:

```ini
Mode=0
```

Super Resolution remains active.

## Requirements

Complete the first three steps in the root README first:

1. FusionFix 5.0.1;
2. DLAA baseline;
3. working ReShade b-bridge input patch.

For the reproducible local build used by this installer you also need:

- Git for Windows;
- Python 3 in `PATH`;
- Visual Studio 2022 Build Tools;
- Desktop development with C++ / x86+x64 MSVC tools;
- Windows SDK;
- internet access.

For NR execution, the tested 310.8.0-RTX40 runtime requires NVIDIA driver **615.00 or newer**. The tested project GPU is RTX 4070 Ti SUPER.

## Verification

Main log:

```text
GTAIV\.trex\dlss5-feed.log
```

Successful startup-prime evidence includes:

```text
M3K-A3-S5: STARTUP PRIME armed 1485x835
M3K-A3-S5: STARTUP PRIME COMPLETE after 180 synchronized SR frames
M3K-SR-LIVE: ACTIVE <saved mode> ...
```

When NR is ON (`Mode=2`), native validation should also show successful Feature 18 creation/evaluation. The proven native path has produced evidence such as:

```text
M3K-A0: DLSS NR runtime found
M3K-A0: feature 18 creation SUCCESS
M3K-A1: feature 18 evaluation SUCCESS
M3K-A2-S2.6: NR18 -> DLAA running ...
```

See [`VERIFY.md`](VERIFY.md).

## Rollback

The installer creates:

```text
_DLSS_FULL_PREINSTALL_BACKUP_<timestamp>
```

beside `GTAIV.exe` and records its path in `DLSS_FULL_INSTALLED.txt`.

Close GTA IV and `NvRemixBridge.exe` before restoring files from that backup.
