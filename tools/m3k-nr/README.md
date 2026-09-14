# M3K native NR -> DLAA test

Experimental. See `docs/M3K-NR.md` at the repository root for the source contract,
validation limits, and implementation details. No real GTA/feature-18 hardware
validation is claimed by a successful build.

From the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\m3k-nr\build.ps1
```

Requires Git and Visual Studio C++ x64 Build Tools/Windows SDK. The script fetches
only pinned source/SDK dependencies, compiles the Feeder add-on and caller shim,
runs CPU tests, and writes `tools/m3k-nr/out-m3k/`. It never installs anything.

## Manual test installation

1. Exit GTA IV and `NvRemixBridge.exe`. Back up your existing
   `GTAIV\.trex\dlss5-feed.addon64` outside the ReShade add-on search folder.
2. Copy `out-m3k\dlss5-feed.addon64` to
   `GTAIV\.trex\dlss5-feed.addon64`, replacing that one file. Do not leave a
   second `.addon64` copy beside it.
3. Copy `out-m3k\m3k-nr.ini` to `GTAIV\.trex\m3k-nr.ini`.
4. Create `GTAIV\.trex\m3k\`. Copy `out-m3k\m3k\m3k-nvngx.dll` into it.
5. Supply your RTX-compatible `nvngx_dlssnr.dll` at
   `GTAIV\.trex\m3k\nvngx_dlssnr.dll`. This DLL is not generated or downloaded.
   The repository's recorded RTX 40 candidate is 310.8.0, SHA256
   `4b8d19bc3eff58a084f5eca7489c921501c203450169fb82ff4f649a4482ba05`;
   its compatibility with M3K is still unverified.
6. Keep your existing `.trex\nvngx_dlss.dll`, `dlss5-feed.cfg`, ReShade shaders,
   input patch, and b-bridge configuration. Feeder must use `enabled=1`, `mode=2`,
   `work_resolution=100`; use the normal 2560x1440 game resolution for the first test.
   M3K requires the DLAA-only baseline: no DFC/RenoDX/OptiScaler NR consumer should
   be loaded concurrently. If one is present, retire it manually before testing.

There are exactly two generated runtime binaries to copy: the add-on and the
shim. Nothing goes beside the 32-bit `GTAIV.exe`; no global ReShade DLL changes.
`m3k-tests.exe`, build reports, and licenses are not game components. Preserve
the supplied NOTICE/licenses if sharing the built package.

## A0 / A1 / bypass

Change `[M3K] Mode` in `.trex\m3k-nr.ini`; it is polled once a second while the
Feeder Vulkan effect is running. Wait for the mode log before comparing images.

| Mode | Behavior |
|---|---|
| `0` (default) | NR unloaded; original GTA color -> existing DLAA |
| `1` | A0: discover, attach, create feature 18; original GTA color -> existing DLAA |
| `2` | A1: raw GTA color -> native NR output -> existing DLAA |

Start with `0`, verify your baseline, then use `1` and verify the displayed image
is unchanged. `2` enables NR without swapping binaries. To retry an NR failure,
set `0`, wait for its log, then set `1` or `2`. Failures latch NR off for that
runtime lifetime; GPU faults may require restarting the game.

Look in `GTAIV\.trex\dlss5-feed.log` for these **expected**, unverified GPU lines:

```text
M3K-A0: DLSS NR runtime found
M3K-A0: feature 18 creation SUCCESS
M3K-A1: feature 18 evaluation SUCCESS
M3K-A1: DLAA color source=NR output; temporal history reset=1
M3K-A1: DLAA running after NR
M3K-A0: feature 18 released
```

Result logs include dimensions, reset state, style and NGX error codes. A0 success
requires successful creation **and** retirement of its initialization commands.
A1's CPU return success alone does not prove correct GPU pixels or temporal quality.
Normal teardown or switching to `0` releases NR after a queue fence; process-exit
teardown may deliberately skip runtime calls and log retained resources.

Rollback: exit GTA/bridge, restore the backed-up Feeder add-on, and remove the
test-only `m3k-nr.ini` and `m3k` folder you created. The build never changes the
known-good installation for you.
