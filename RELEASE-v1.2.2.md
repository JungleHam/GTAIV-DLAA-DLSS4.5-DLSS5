# GTA IV Scaling v1.2.2

v1.2.2 is a focused installer hotfix on top of v1.2.1.

## Fixed

- Fixed installation failing with **FusionFix CFG not found** even though FusionFix had completed its first run.
- The foundation installer now checks the same supported FusionFix config locations as the main setup:
  - `GTAIV\plugins\GTAIV.EFLC.FusionFix.cfg`
  - `GTAIV\GTAIV.EFLC.FusionFix.cfg`
  - `%LOCALAPPDATA%\Rockstar Games\GTA IV\GTAIV.EFLC.FusionFix.cfg`
  - `%LOCALAPPDATA%\GTAIV.EFLC.FusionFix\GTAIV.EFLC.FusionFix.cfg`
  - Documents `\GTAIV.EFLC.FusionFix\GTAIV.EFLC.FusionFix.cfg`
  - plus the existing `*FusionFix*.cfg` fallback inside the game `plugins` folder.

## Unchanged

- RTX 20/30 Neural Rendering support from v1.2.1.
- RTX 40/50 NR paths.
- DLAA/DLSS, FSR 3.1.4, RCAS, temporal calibration and live backend switching.
- The two uninstall modes introduced in v1.2.1.
