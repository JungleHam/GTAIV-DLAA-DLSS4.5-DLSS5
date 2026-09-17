# Installers

Normal release flow:

| Step | Run | Result |
|---|---|---|
| 1 | [FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix) | Required GTA IV baseline. |
| 2 | **`Install-DLAA.bat` as Administrator** | DLAA + official ReShade + verified prebuilt input patch. |
| 3 | **`Install-DLSS-Full.bat` as Administrator** | Verified prebuilt DLSS runtime + Neural Rendering + in-game controls. |

Both BATs ask for the folder containing `GTAIV.exe`, show the selected install, and wait for one confirmation.

**Normal users do not need Git, Python, Visual Studio Build Tools, or a manual ReShade install.** Source-build scripts under `install/core/` and `tools/` are for development/reproducibility only.

After Step 3:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

## Uninstall

**`Uninstall-DLSS-Full.bat`** removes DLSS Full and restores the preserved DLAA baseline.

**`Uninstall-DLAA.bat as Administrator`** removes the entire project stack and restores the exact GTA IV + FusionFix state captured before Step 2. FusionFix itself stays installed.

See the root [README](../README.md) for the short release guide.
