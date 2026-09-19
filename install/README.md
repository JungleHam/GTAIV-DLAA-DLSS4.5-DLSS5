# Installer files

Normal users should use `GTAIV-DLSS-Setup.exe` from this project's GitHub Releases page after the cleaned installer is rebuilt.

The intended release flow is deliberately beginner-friendly:

1. Make one temporary folder such as `Desktop\GTA IV DLSS Setup Files`.
2. Put `GTAIV-DLSS-Setup.exe` in it.
3. Put every prerequisite file setup asks you to download into that same folder.
4. Do **not** extract ZIPs, run ReShade manually, or copy prerequisite files into GTA IV.
5. Setup validates and installs/extracts them.

The future installer can accept a user-supplied `GTAIV.EFLC.FusionFix.zip` if FusionFix is missing. FusionFix requires one normal game launch before the DLAA/DLSS installation can continue, so setup may perform that prerequisite installation first and ask the user to launch GTA IV once and rerun setup.

For a fresh install setup can then use:

- official ReShade 6.8.0 **Full Add-On Support** installer;
- official pinned LumeniteFX ZIP;
- for Full DLSS, the correct GPU-matched Neural Rendering ZIP.

For Neural Rendering, setup opens the **`RankFTW/rhi-repo` repository root**, tells the user to click **Releases** in the right sidebar, and explains that the tested 310.8.0 releases are older and may require clicking **Next** through the Releases list a couple of times. It also warns not to confuse `RankFTW/rhi-repo` with the separate `RankFTW/RHI` repository.

The complete click guide is in [`../docs/PREREQUISITES.md`](../docs/PREREQUISITES.md).

The installer opens only GitHub project pages and never embeds a direct third-party binary/archive asset URL. Git, Python and Visual Studio Build Tools are not required for release installs.
