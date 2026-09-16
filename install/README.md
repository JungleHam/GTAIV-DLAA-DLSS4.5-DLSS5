# Install modules

Recommended order:

```text
1. FusionFix 5.0.1 (external prerequisite)
2. Install-DLAA.bat
3. ReShade b-bridge input patch
4. Install-DLSS-Full.bat
```

## DLAA

`Install-DLAA.bat` creates the known-good b-bridge/ReShade/Feeder DLAA baseline from a clean FusionFix installation.

It installs `nvngx_dlss.dll` 310.9.1 but does not install/enable the DLSS 5 NR runtime yet.

## ReShade input fix

Build `tools/reshade-bbridge-input/BUILD.bat`, then **right-click `INSTALL.bat` → Run as administrator**.

Do not continue until Home opens ReShade and mouse/keyboard input works.

## DLSS 4.5 SR + DLSS 5 NR

`Install-DLSS-Full.bat` is the current combined module. It adds:

- A3-S2 coherent draw-boundary jitter;
- UQ77 / Quality / Balanced / Performance / Ultra Performance SR profiles;
- A3-S5 automatic `1485x835` startup prime;
- automatic return to the saved SR profile;
- the pinned RTX40-compatible `nvngx_dlssnr.dll` 310.8.0 runtime;
- native M3K Feature 18 integration.

Neural Rendering is **installed but OFF by default**:

```ini
Mode=0
NRPasses=1
```

The installer also places `DLSS-Full-Control.bat` beside `GTAIV.exe`.

Use it to:

```text
1..5  choose the saved DLSS 4.5 SR profile
N     turn DLSS 5 NR ON  (Mode=2)
O     turn DLSS 5 NR OFF (Mode=0)
L     launch through the 1485x835 startup prime
```

There is no separate Deep Fried Chicken module in the current install path.

Read [`../docs/DLSS-FULL.md`](../docs/DLSS-FULL.md) and [`../docs/DLSS5.md`](../docs/DLSS5.md).

## Backup

`Backup-Working-Stack.bat` snapshots the current integration, including:

- A3-S2 `d3d9.dll`;
- A3-S5 Feeder/config;
- `.trex/m3k-nr.ini`;
- `.trex/m3k/m3k-nvngx.dll`;
- `.trex/m3k/nvngx_dlssnr.dll`;
- ReShade/DLAA integration files.

The install scripts also create timestamped rollback backups before replacing runtime files.
