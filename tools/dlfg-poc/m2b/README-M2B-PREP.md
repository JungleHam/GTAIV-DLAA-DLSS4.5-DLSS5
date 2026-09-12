# M2B: real-resource, off-screen DLSS-G experiment

M2B-PREP has passed on the hardware tester. M2B has also passed an off-screen two-frame evaluation with Deep Fried Chicken (DFC) physically absent: create, reset=1, reset=0, and CPU readback succeeded, with generated output differing from both source frames. This folder now also contains M2C-A, a default-off coexistence root-cause test for DFC present and ARMED. Neither milestone is presentation or a claim that GTA IV frame generation works.

## Confirmed architecture

The installed `dlss5-feed.addon64` is DLSS 5 Feed `0.15.1`, matched to upstream tag `v0.15.1` (`3f624855276c4bde55145c712782477639b30e85`). GTA IV's Vulkan route is Vulkan-to-D3D12 transport, not Vulkan NGX:

1. ReShade exposes live Vulkan images for the game colour/backbuffer, LumeniteFX motion vectors, and depth.
2. `FeedFrameVk` copies them into `g.vk_img[SLOT_COLOR/DEPTH/MV]`, Vulkan imports of shared D3D12 resources.
3. The Feeder's stable private D3D12 device owns `g.tex12[SLOT_COLOR/OUTPUT/DEPTH/MV]`, `g.queue`, `g.list`, `g.params`, and the existing DLAA feature `g.feature`.
4. The Feeder initializes NGX once through `NVSDK_NGX_D3D12_Init` and runs the normal DLAA/Deep Fried Chicken call through D3D12 NGX. M2B allocates its own DLSS-G parameter/feature handles in that already-running session. It does not call any second NGX init or shutdown.

The input to DLSS-G is exactly `g.tex12[SLOT_OUTPUT]` after the normal DLAA/DFC evaluate: the current final resolved real frame. The depth and motion-vector inputs are `g.tex12[SLOT_DEPTH]` and `g.tex12[SLOT_MV]`. The other surrounding real frame is captured on the immediately preceding valid Feeder frame.

## Safety and one-shot behavior

`dlfg_m2b_probe=0` and `dlfg_m2b_eval=0` are compiled defaults. With both at zero, M2B is inert. `probe=1` retains the M2B-PREP handle log every 300 frames. `eval=1` performs at most one temporal pair:

- It waits for the existing 600-frame guide probe to see non-flat finite real depth. Flat startup/menu depth logs `M2B: skipping DLSS-G: depth invalid/flat` and does not arm.
- It creates a private 2560x1440 `B8G8R8A8_UNORM` D3D12 interpolated-output texture plus private CPU readback buffers.
- It records reset=true on real frame A, then reset=false on the next valid real frame B, using `multiFrameCount=1`, `multiFrameIndex=1`.
- It uses the existing D3D12 list/queue/fence. The output is copied to CPU readback only, not to `SLOT_OUTPUT`, the Vulkan backbuffer, or any present path.
- On a later Feeder frame, after the existing fence proves completion, it writes `.trex\dlfg-m2b-generated.bmp`, logs checksum/statistics/differences, and only then logs `MILESTONE 2B PASSED` if the result is non-empty and differs from both real frames.

Camera mode is explicitly approximate because GTA IV camera matrices are not exported by the current Feeder. It uses a non-jittered 60-degree, near=0.1, far=1000 D3D perspective and identity current/previous camera transforms. `DLSS5_Feed.fx` writes pixel-space current-to-previous displacement (`prev_uv = uv + mv`); M2B converts that texture for DLSS-G with `mvecScale = { 1/width, 1/height }` (at 2560x1440: `0.000390625`, `0.000694444`). This is intentionally separate from, and does not alter, DLAA's existing `mv_scale_x/y`. `depthInverted` follows the existing Feeder depth setting.

The Feeder itself adds or changes no `vkQueuePresentKHR` call; presentation is
owned by the separately gated OptiScaler Vulkan experiment.

## M3B-1 producer

The same experimental Feeder now has a default-off `dlfg_m3b1_present=0` mode.
It reuses the existing D3D12 NGX session and the M2B feature-11 A/B evaluation,
but directs the genuine generated output into M3B-1A's dedicated shareable
D3D12/Vulkan image. Publication uses the unchanged M3B-1A ABI and
`fence12_out -> vk_sem_out` timeline value. A small optional provenance export
lets OptiScaler distinguish validated feature-11 output from the unchanged
M3B-1A post-NR copy without changing that ABI.

## M2C-A: DFC / DLSS-G coexistence root-cause test

**M2C-A concluded on the RTX 4070 Ti SUPER test rig:** at the earliest Feeder
`CreateDlssFeature` checkpoint, DFC was already `ARMED`; the same was true on
the subsequent normal rebuild. No `CLAIMING` state was observable to Feeder and
no feature-11 Create was attempted. This rules out another Feeder timing move.
The established A/B remains: with DFC absent, feature-11 Create plus two
off-screen evaluations succeeds; with DFC ARMED, the normal post-arm Create
returns `PlatformError`.

M2C-B requires an author-provided DFC source/experimental build with feature-11
logging and a default-off forwarding test. The distributed DFC licence permits
only unmodified official binaries, so this repository does not patch or reverse
engineer the DFC binary.

`dlfg_m2c_prearm_create=0` is the compiled default. When set to `1` **with the normal DFC add-on present and armed**, it uses no extra device, queue, NGX initialization, NGX shutdown, hook, or DFC ABI write. At the earliest point in the existing `CreateDlssFeature` command list—after the private D3D12 session and shared textures exist, but before normal feature-1/DLAA Create—it checks the DFC export. It creates feature 11 only while that export says `CLAIMING`; it retains that separate DLSS-G parameter/feature pair and waits for a later normal DLAA/DFC frame to succeed after the export changes to `ARMED`. Only then does it run M2B's same private-output, two-frame off-screen readback experiment.

DFC's ABI-1 documentation states that it forwards feature 11, feature 13, and unknown NGX features to the genuine target, while adopting only the marked feature-1 contract. The public protocol supplies no producer-callable original/trampoline entry point, passthrough switch, or feature filter. M2C-A therefore does not bypass or alter DFC: it tests that documented forwarding boundary directly. The feature-1 `DFC.Feeder.*` marker remains exclusive to the normal DLAA/DFC feature; M2C never applies it to DLSS-G.

The result categories are explicit in `dlss5-feed.log`:

- `M2C: pre-arm ... -> Success`, both `M2C: reset=1/0 -> ... Success`, successful readback, and `MILESTONE 2C PASSED`: coexistence worked.
- successful pre-arm Create followed by failed evaluate: DFC did not preserve the feature-11 evaluation path.
- failed pre-arm Create: DFC rejected feature 11 even before `ARMED`.
- `pre-arm feature was invalid after DFC armed`: the created feature became invalid across the DFC transition.

Resource rebuild releases the retained feature/history with the normal Feeder resource teardown. If no coexistence evaluation has yet been attempted, a later build may only recreate through the same `CLAIMING` pre-arm policy; it never creates a new feature after `ARMED`. There is at most one M2C two-frame coexistence evaluation per process.

## Build and hardware test

1. Run `tools\dlfg-poc\GET-RUNTIME.bat` once if `tools\dlfg-poc\nvngx_dlssg.dll` is absent. It obtains the NVIDIA runtime locally; the DLL is not committed or packaged.
2. Run `tools\dlfg-poc\m2b\BUILD-M2B-PROBE.bat`. It builds `m2b-build\dlss5-feed-m2b-eval.addon64` only; it does not touch GTA IV.
3. Close `GTAIV.exe` and `NvRemixBridge.exe`. Run `INSTALL-M2B-PROBE.bat`, inspect its target, and type `INSTALL`. It makes an active snapshot of only the current Feeder add-on/config and prior `nvngx_dlssg.dll` state, then copies the experimental add-on/runtime into `.trex` and appends the M2B settings. It refuses to overwrite an active snapshot.
4. For the M2C-A test only, leave the normal DFC add-on and its configuration unchanged, then append exactly `dlfg_m2c_prearm_create=1` to `.trex\dlss5-feed.cfg`. Do not set it for an ordinary M2B test.
5. Start GTA IV normally, enter real moving gameplay for at least 12 seconds, then continue moving for a few seconds after the evaluator logs its readback. Do not alter any other stack component.
6. Close the game. Read `.trex\dlss5-feed.log` and inspect `.trex\dlfg-m2b-generated.bmp`. Then run `RESTORE-M2B-PROBE.bat` and type `RESTORE` to restore only those backed-up files. A successful restore moves its completed snapshot into `backup\archive\<timestamp>` so the next install makes a fresh live-state snapshot. It also recognizes legacy root-level M2B-PREP backups. The BMP is a diagnostic and is intentionally left for inspection.

An old M2B-PREP root-level backup without a runtime-state marker is never overwritten. If its live config has no M2B settings, the installer explains that it will archive those legacy files unchanged after `INSTALL`, then records the current runtime state in the new active snapshot. If that incomplete legacy backup still belongs to an active test, the scripts stop for manual recovery rather than guessing its runtime state.

Success requires log lines for `NGX_D3D12_CREATE_DLSSG -> ... Success`, both `NGX_D3D12_EVALUATE_DLSSG(... reset=1/0) -> ... Success`, `output copied to CPU readback`, `readback completed`, non-zero differences from both Frame A and Frame B, and finally `MILESTONE 2B PASSED`.

The scripts refuse to run while GTA IV or the bridge is running. They do not alter `GTAIV.exe`, DXVK, ReShade, b-bridge, `NvRemixBridge.exe`, global Vulkan layers, or graphics/driver settings.
