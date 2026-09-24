# GTA IV Scaling v1.2.1

v1.2.1 extends DLSS 5 Neural Rendering support to RTX 20 and RTX 30 Series GPUs while preserving the v1.2.0 scaling and switching baseline.

## Changes

- RTX 20 Series: Neural Rendering is now installed and exposed in the Home-key GTA IV Scaling controls.
- RTX 30 Series: Neural Rendering is now installed and exposed in the Home-key GTA IV Scaling controls.
- RTX 20/30 use the ShortFuse **310.8.SF-v2** compatibility runtime.
- RTX 40 keeps the existing project-tested **310.8.0 RTX40 compatibility** runtime.
- RTX 50 keeps the existing **NVIDIA-signed 310.8.0** runtime and signature validation.
- Neural Rendering still starts **OFF by default** on every supported RTX generation.
- Uninstall now offers **keep FusionFix** and **complete cleanup including FusionFix** modes.
- Both uninstall modes remove GTA IV Scaling receipts/logs and `_GTAIV_SCALING_PRE*_BACKUP_*` rollback folders.
- Existing Off / NVIDIA / AMD switching, FSR 3.1.4, RCAS, DLSS/DLAA profiles, sharpening and temporal calibration are unchanged.

## Runtime integrity

RTX 20/30 ShortFuse package:

- archive: `nvngx_dlssnr_310.8.SF-v2.zip`
- archive SHA256: `1DA35941894994EB087E017577829E492454E9BAE3A6A9397027069CEB74955C`
- extracted `nvngx_dlssnr.dll` SHA256: `6EB209E764F39872625DEBD6ABAF45E2BB6322F6F270F781F70C059AE30B3927`

The installer downloads the GPU-matched package from the pinned RankFTW/rhi-repo release and verifies the archive and DLL before installation.

## Compatibility note

The RTX 20/30 NR path uses a modified compatibility runtime rather than an NVIDIA-signed production NR DLL. The installer does not apply the RTX 50 Authenticode requirement to the ShortFuse path.

All v1.2.0 backend-lifecycle and temporal-calibration behavior remains unchanged.
