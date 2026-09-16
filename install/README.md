# Install modules

Recommended order:

```text
1. FusionFix 5.0.1 (external prerequisite)
2. Install-DLAA.bat
3. ReShade b-bridge input patch (recommended for interactive UI)
4. Install-DLSS-Full.bat
5. Optional Neural Rendering module
```

## DLAA

`Install-DLAA.bat` creates the project's known-good b-bridge/ReShade/Feeder DLAA baseline.
Start here from a clean FusionFix installation.

## DLSS Full

`Install-DLSS-Full.bat` upgrades that working DLAA baseline to the hardware-validated
Super Resolution path:

- A3-S2 coherent draw-boundary jitter
- UQ77 / Quality / Balanced / Performance / Ultra Performance profiles
- A3-S5 automatic 1485x835 startup prime
- automatic return to the saved SR profile
- Neural Rendering left disabled (`Mode=0`)

The installer also places `DLSS-Full-Control.bat` beside `GTAIV.exe` for profile selection
and the recommended primed launch path.

Read [`../docs/DLSS-FULL.md`](../docs/DLSS-FULL.md) for requirements and verification.

## Neural Rendering

Neural Rendering remains a separate optional layer after DLSS Full. The existing
`Upgrade-DLSS5-DFC.bat` is the repository's older DFC-based NR integration; the newer
native M3K Feature-18 path is being packaged separately. Do not assume the older DFC
upgrade has been revalidated on top of DLSS Full unless its documentation explicitly says so.

## Backup

`Backup-Working-Stack.bat` remains available for manual snapshots. Both DLAA and DLSS Full
installers also create their own timestamped rollback backups before replacing runtime files.
