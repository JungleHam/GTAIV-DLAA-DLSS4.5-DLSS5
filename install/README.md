# Installers

Normal release flow:

| Step | Run | Result |
|---|---|---|
| 1 | [FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) | Required GTA IV baseline. |
| 2 | **`Install-DLAA.bat` as Administrator** | DLAA + ReShade + cross-process input patch. |
| 3 | **`Install-DLSS-Full.bat` as Administrator** | DLSS Super Resolution + DLSS 5 Neural Rendering + in-game controls. |

Both BAT installers ask for the folder containing `GTAIV.exe`, show what will be installed, and wait for one confirmation.

The `install/core/` scripts are implementation files used by the release-facing installers. Normal users should not run them directly.

After Step 3, settings are in:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

## Uninstall

**`Uninstall-DLSS-Full.bat`** removes DLSS Full and restores the preserved DLAA baseline.

**`Uninstall-DLAA.bat` as Administrator** removes the entire project stack and restores the exact GTA IV + FusionFix state captured before Step 2. It also removes the ReShade Vulkan/input patch installed by this project. FusionFix itself stays installed.

`Uninstall-DLAA.bat` can be run while either DLAA-only or DLSS Full is installed. It asks for the GTA IV folder and requires one confirmation.

See the root [README](../README.md) for prerequisites and the short install guide.
