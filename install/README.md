# Installers

For normal users, use **`GTAIV-DLSS-Setup.exe`** from the GitHub Release. It provides one UI for install, repair, upgrade, partial removal, and full removal.

The setup offers:

| Action | Result |
|---|---|
| **Install / repair DLAA** | DLAA + official ReShade + verified input patch |
| **Install / repair Full DLSS** | Automatically ensures DLAA first, then adds DLSS 4.5 + DLSS 5 NR |
| **Remove DLSS Full only** | Restores the preserved DLAA baseline |
| **Remove everything** | Restores the saved GTA IV + FusionFix baseline |

The BAT files in this folder remain available as manual/fallback tools. Run them as **Administrator**.

**Normal users do not need Git, Python, Visual Studio Build Tools, or a manual ReShade install.** Source-build scripts under `install/core/` and `tools/` are for development/reproducibility only.

After Full install:

```text
Home -> Add-ons -> DLSS 5 Feed -> GTA IV DLSS
```

See the root [README](../README.md) for the short release guide.
