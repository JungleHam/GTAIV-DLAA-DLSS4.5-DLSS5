# FSR P1 hardware proof

Status: experimental, disabled by default.

P1 exists to answer one question before the public backend/UI work starts:

> Can GTA IV's proven low-resolution color + depth + Lumenite motion vectors + bridge jitter drive FidelityFX FSR 3.1.4 directly on the existing Vulkan command buffer and return a live native-resolution frame?

## Safety contract

- `main` / v1.1.0 is not modified.
- Normal behavior is unchanged when `FSRProof=0`.
- P1 never destroys/recreates an FSR context during runtime/device churn.
- If FSR context/device/output contracts change, P1 latches itself off and the existing DLSS path remains the fallback.
- RCAS is off.
- Frame Generation is not present.
- Neural Rendering is not part of P1.
- The production installer/release workflow is not modified.

## Temporary P1 dependency

P1 deliberately reuses the already-proven DLSS SR resolution split to make GTA IV render below presentation resolution. On an FSR-successful frame, however, NGX/DLSS is **not evaluated**:

```
GTA IV low-res render
  -> DXVK source tap
  -> low-res color + scaled R32F depth + scaled RG16F motion vectors
  -> FSR 3.1.4 Vulkan
  -> imported native-size OUTPUT VkImage
  -> direct Vulkan copy to GTA IV backbuffer
```

After the temporal mapping is hardware-proven, P2 removes DLSS/NGX from resolution planning so FSR becomes a real independent backend.

## Activation

The candidate is intentionally hidden. Add this to `m3k-nr.ini`:

```ini
[M3K]
FSRProof=1
```

Set `FSRProof=0` (or remove the line) for normal production behavior.

Use one of the existing non-native reconstruction modes first, e.g. Quality/67%, so the proven low-resolution split exists.

## Current provisional inputs

These are sufficient for a proof that FSR creates/dispatches/returns live output, but **not** for a final image-quality verdict:

- Jitter: exact bridge-published raster jitter, passed to FSR without the NGX-specific compensation.
- Motion vector scale: `1,1`, based on the current Lumenite provider's pixel-space contract.
- Camera near: `0.1`.
- Camera far: `1000`.
- Vertical FOV: `70 degrees`.
- Reactive mask: none.
- Transparency/composition mask: none.
- Auto exposure: on.
- RCAS: off.

Camera values can be overridden for experiments:

```ini
FSRCameraNear=0.1
FSRCameraFar=1000
FSRCameraFovYDegrees=70
```

The bridge does not yet publish authoritative GTA IV near/far/FOV. That is a P2 input-calibration task.

## Expected proof logs

A successful start should contain lines similar to:

```text
M3K-FSR-P1: FSRProof=1
M3K-FSR-P1: FSR 3.1.4 Vulkan context READY ...
M3K-FSR-P1: FSR DIRECT Vulkan frame=1 ...
[feed] frame ... delivered by FSR 3.1.4 DIRECT Vulkan proof
```

AMD debug-checker warnings are emitted as:

```text
M3K-FSR-DEBUG: ...
```

## First visual checks

For P1, judge only transport/reconstruction behavior:

1. Is the picture live rather than frozen/stale?
2. Is the output actually reconstructed rather than a raw low-resolution stretch?
3. Does a static camera settle temporally?
4. Do camera pans produce gross smearing or reversed motion?
5. Does disabling `FSRProof` return cleanly to the existing DLSS path on restart?

Do **not** compare fine quality against DLSS yet. Near/far/FOV, MV sign/scale, reactive masks and final backend-independent resolution control still need calibration.

## P1 success criterion

P1 passes when FSR repeatedly dispatches on hardware, returns live native-resolution frames, and shows temporal accumulation consistent with the supplied jitter/MVs without destabilizing the production DLSS fallback.
