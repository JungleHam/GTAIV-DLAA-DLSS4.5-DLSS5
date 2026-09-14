# M3K: native feature 18 before the existing DLAA pass

## Baseline and scope

Base: `main` at `ccd971b1ae71476b522899cf6243686e3a256920`.
The remote branch inventory and main source/manifests were inspected. Main is
the smallest matching baseline: Feeder 0.15.1 native DLAA, Lumenite guides, and
the ReShade 6.8.0 b-bridge input patch, with no required FG runtime. Main's
optional DFC installer is a separate **DLAA -> NR** integration; M3K does not
use it. No M3B/M3C/M3H/M3I implementation was imported or required.

Branch: `gtaiv-m3k-nr-baseline`. Main and the historical experiments remain intact.
The target is an integration/installer repository rather than a Feeder source
fork. Accordingly, M3K adds a reviewable patch against immutable Feeder source
`3f624855276c4bde55145c712782477639b30e85` (v0.15.1) plus four small headers/source
files. The build downloads that source into an ignored staging directory.

## What was verified in AIO source

Read-only reference: [DLSS5 ReShade AIO at 09301f5](https://github.com/kibblerz/DLSS5-Reshade-AIO/tree/09301f5528e619e8b9ec17c257d167e2985f53b0).
The reference checkout was not edited. These findings are source/recorded-lab
evidence, not independent M3K GPU measurements.

| Contract | Evidence and chosen M3K behavior |
|---|---|
| Native transformation | [PRIVATE-CONTRACT-FINDINGS.md](https://github.com/kibblerz/DLSS5-Reshade-AIO/blob/09301f5528e619e8b9ec17c257d167e2985f53b0/lab/PRIVATE-CONTRACT-FINDINGS.md): all explored enlargement paths still wrote an input-sized rectangle. Use 2560x1440 input and output, then separate feature-1 DLAA. |
| Runtime entry | [`nvngx-bridge.cpp`](https://github.com/kibblerz/DLSS5-Reshade-AIO/blob/09301f5528e619e8b9ec17c257d167e2985f53b0/addon/src/nvngx-bridge.cpp) and `InitializeNgx` in [`nr-standalone.cpp`](https://github.com/kibblerz/DLSS5-Reshade-AIO/blob/09301f5528e619e8b9ec17c257d167e2985f53b0/addon/src/nr-standalone.cpp): direct snippet exports, not public-facade feature-18 discovery. `Init_Ext(0x876232C, full NR DLL path, device, API version 0x15, nullptr)` crosses a non-tail-called module whose filename contains `nvngx.dll`. |
| Parameters | `SetNrCreationContract` / `SetNrEvaluationContract` in `nr-standalone.cpp`; `SetCreationContract` / `SetEvaluationContract` in [`nr-lab.cpp`](https://github.com/kibblerz/DLSS5-Reshade-AIO/blob/09301f5528e619e8b9ec17c257d167e2985f53b0/lab/nr-lab.cpp). `PopulateParameters_Impl` installs provider callbacks; a parameter Reset removes them. M3K allocates a separate NGX parameter object, populates once, and never resets it between NR and SR. |
| Default look | Style 0, hint preset 1, strength values 1.0, internal auto-mask on, UI correction off. Recorded lab results identify Style 0/1/2 as the effective network choice; hint presets did not change those test outputs. |
| Runtime callback | The lab registers one to trace/change private live fields; production `nr-standalone.cpp` does not register `SetRuntimeParamsCallback`. Recorded scaling defaults to 1.0. M3K omits this optional global callback for 1:1. This differs from the provider callbacks installed by PopulateParameters, which M3K retains. |
| Ordering | AIO records NR writes, transitions its output UAV -> non-pixel SRV, then evaluates SR using that texture. M3K follows the same ordering on Feeder's existing D3D12 queue/list. |
| Destruction | Release through the snippet's `ReleaseFeature`, destroy the NR parameter object, then call the snippet's `Shutdown1`; wait for GPU retirement before freeing textures/modules. M3K leaves Feeder's core/SR lifecycle with Feeder. |

The headers implementing AIO-derived behavior carry Apache-2.0 notices, a copy
of AIO's NOTICE attribution, and the full license. The Feeder adapter/patch and
original tooling retain MIT notices. Nothing from AIO's compositor, NVOF, x86
host, D3D9 capture, or FG implementation is built.

## Exact creation/evaluation contract

Creation uses feature ID **18**, node masks 1, equal `Width/Height`,
`OutWidth/OutHeight`, resource dimensions, `DLSSNR.*` dimensions and `Output.*`
dimensions. `PerfQualityValue=DLAA (5)`, output subrects off, denoise mode 1,
roughness mode 0, hardware depth on. NR receives Feeder's existing feature flags
(including its depth convention, HDR and MV-low-resolution settings).
`DLSSNR.Enabled=1`, `ScalingRatio=Scale=1.0`, Style 0 / hint 1. The private
`DLSSNR.Upscaling=1` provider switch is preserved from AIO's native path; it does
**not** enlarge any allocation or select SR scaling.

Evaluation binds both public and private aliases for Color, Output, Depth and
MotionVectors/MVec. Reset, jitter and MV scales are copied from the exact DLAA
evaluation structure for that source frame. NR subrect keys use **signed int**
base coordinates 0 and native widths/heights. Public render dimensions remain
unsigned. No ControlMask, UI, UIAlpha, Backbuffer, or distortion resource is
bound. Exposure values are copied unchanged. Camera matrices are not newly
invented or synthesized: the baseline Lumenite/Feeder contract remains in use.

| D3D12 resource | Format / usage | State at NR evaluation |
|---|---|---|
| Existing real color | BGRA8 UNORM, RGBA8 UNORM, or RGBA16 FLOAT; baseline single-sample texture | NON_PIXEL_SHADER_RESOURCE |
| Existing depth | R32_FLOAT, native dimensions | NON_PIXEL_SHADER_RESOURCE |
| Existing motion | R16G16_FLOAT, native dimensions | NON_PIXEL_SHADER_RESOURCE |
| Private NR output | RGBA8 UNORM for SDR; RGBA16_FLOAT for HDR; DEFAULT heap, single mip/sample, ALLOW_UNORDERED_ACCESS; typed-store support checked | UNORDERED_ACCESS |
| Existing DLAA output | Baseline texture/format unchanged | UNORDERED_ACCESS |

Color/guide input flags and Vulkan ownership transfers remain exactly as in
Feeder. NR output is never shared with Vulkan. Its UAV -> SRV transition orders
NR writes before DLAA reads; after DLAA recording it transitions back to UAV.
All original inputs return to COMMON through the unchanged Feeder code.
Queue order prevents reuse of the NR output ahead of the previous DLAA read.

## Implemented architecture

**Mode 0:** no NR runtime load/create/evaluate. Original raw color -> original
DLAA evaluation -> existing normal presentation.

**Mode 1 / M3K-A0:** load `.trex/m3k/nvngx_dlssnr.dll` and
`.trex/m3k/m3k-nvngx.dll`, attach NR to Feeder's device using its already-open NGX
environment, allocate separate parameters, and create feature 18. Creation has
its own temporary command recording on the same queue; success is logged only
after that recording retires. No evaluation or NR output allocation is needed.
The original DLAA color pointer and complete temporal contract are retained.

**Mode 2 / M3K-A1:** reuse/create feature 18, allocate one private native output,
evaluate NR from the existing raw input and same-frame guides, then replace
only the copied DLAA structure's color pointer with NR output. DLAA still uses
its original handle, parameters, depth, motion, jitter, exposure and mask.
First NR evaluation and re-enabling NR reset NR history; changing the actual
DLAA color source resets DLAA history. Baseline reset requests also reach NR.
Resolution/device/creation-flag changes retire and recreate NR as needed.

Mode is hot-read once per second from the separate `m3k-nr.ini`. Unsupported
dimensions/formats/modes, missing DLLs, missing exports and allocation/create
failures latch a bypass. A preloaded competing NR runtime is refused. Disable
then enable to retry; there is no per-frame create-failure loop.

If feature-18 evaluation returns failure or raises SEH, **the entire still
unsubmitted D3D12 list is discarded**. The extracted, otherwise unchanged
Feeder input recording is repeated for the same source frame, followed by
ordinary raw-color DLAA with reset. This preserves the queue's existing
Vulkan-input fence wait and never submits partial failed NR commands. Failure
to reopen that recording uses the existing failure path. A failed final list
Close is not reported as a delivered frame.

Teardown drains the queue before NR release. A hung/removed device or failed
release retains owned objects rather than unloading in-flight code/resources;
process-exit teardown may skip runtime calls. These exceptional paths require
a restart and cannot promise recovery of an already-faulted GPU.

## Build, files and manual deployment

See [the build/install README](../tools/m3k-nr/README.md) for the exact command,
two produced runtime binaries, configuration modes, manual copy locations,
rollback and expected logs. No game path is accepted by the build script. It
fetches immutable Feeder, NGX SDK and Vulkan-header revisions; it does not
download an NR runtime, run installers, launch GTA, or modify the installation.

## Validation and remaining GPU work

Directly verified locally on Windows/MSVC x64:

- Pinned-source build and link of the Feeder add-on and caller shim.
- CPU contract tests: native dimensions, typed parameter values/subrects,
  same-frame guide aliases, no UI mask, and reset progression.
- Tests of the real chain adapter with a fake NR/command host: mode polling,
  default-off and A0 bypass, A/B resets, failed NR recording replay, failure to
  resume recording, and SR exception handling. These are not real GPU tests.
- Shim ABI/export/error forwarding and the actual module containing each
  callback's return address, using fake callback functions in an optimized build.
- Patch forward/reverse applicability and source whitespace checks.

**Still unverified on the real RTX GPU:** the pinned NR DLL's acceptance of
Feeder's existing NGX core (AIO's standalone app initializes its own core with
`0x876232C`, while Feeder uses its existing application/project identity), the
private `m3k-nvngx.dll` caller boundary, populated SDK parameter compatibility,
create/evaluate/release success, driver/resource-state validation, 2560x1440
pixel correctness, A0 visual equivalence, temporal quality, cost/VRAM, and
clean resize/quit recovery. These are explicit compatibility hypotheses,
not hardware-pass claims. The API is private and version-sensitive.

Test order: baseline Mode 0 -> A0 Mode 1 (same image) -> A1 Mode 2 -> repeated
0/2 comparisons, then resolution change and normal shutdown. Capture the
`.trex/dlss5-feed.log` and check D3D12/driver errors as well as visual output.
HUD pixels are included in the source color; this first test has no UI
protection. Existing estimated motion-vector limitations still apply.
