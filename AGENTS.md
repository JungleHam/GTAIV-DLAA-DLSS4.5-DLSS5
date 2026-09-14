# Repository agent notes

- `main` is the DLAA + ReShade/b-bridge baseline. M3K is isolated on
  `gtaiv-m3k-nr-baseline`, based on `ccd971b1ae71476b522899cf6243686e3a256920`.
- `tools/m3k-nr` patches Feeder **0.15.1 / 3f624855276c4bde55145c712782477639b30e85**.
  Read `docs/M3K-NR.md` before changing its runtime contract or patch.
- Build/test: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\m3k-nr\build.ps1`.
  Outputs and source dependencies stay in ignored `out-m3k` and `_work` folders.
  Never add game deployment to that script. Do not edit a live GTA installation.
- Mode 0 is default-off; 1 is create-only A0; 2 is native NR -> existing DLAA.
  Preserve same-frame guides, independent NR parameters, failure replay, and
  normal Vulkan presentation. No FG/NVOF/x86 host/compositor belongs in M3K.
- AIO reference is read-only at `09301f5528e619e8b9ec17c257d167e2985f53b0`.
  Keep Apache-2.0 attribution/NOTICE for the marked derived files.
- CPU tests/builds do not establish feature-18 GPU success. Record explicit
  source/build versus real RTX validation in `docs/DAILY.md`; keep main unmerged.
