# Development log

## 2026-09-14 — M3K native NR baseline

- Selected main `ccd971b` and implemented isolated, default-off feature-18
  create-only A0 and NR -> existing DLAA A1 in pinned Feeder 0.15.1.
- Added runtime/shim discovery, separate NR parameters, native UAV output,
  same-frame guide reuse, A/B history reset, failed-recording baseline replay,
  teardown, concise telemetry, pinned build and manual deployment documentation.
- Windows x64 compilation/link and CPU contract/adapter/shim tests passed.
  The test package is in `tools/m3k-nr/out-m3k`; no live GTA files were touched.
- Real feature-18 RTX execution, A0 visual equivalence and A1 quality/performance
  remain untested. Reference AIO and main/FG branches were not changed.
