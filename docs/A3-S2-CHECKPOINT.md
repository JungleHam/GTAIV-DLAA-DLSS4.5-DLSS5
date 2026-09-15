# A3-S2 accepted temporal checkpoint

Accepted hardware checkpoint for GTA IV DLSS SR temporal jitter work.

## Exact base

- Source commit: `6e5d4f3b85399d43d551e3a2557004461b7c3de5`
- Frozen branch: `checkpoint/a3-s2-coherent-jitter`
- Continuation branch: `gtaiv-m3k-a3-post-s2`
- A3-S2 bridge SHA256: `6DD40F145A5D503624E3E05ECF0ADBAA094CF83B24278C0BB333318E3C52A912`
- A3-S1.2 capture Feeder SHA256: `2B89FFE6A9F7DB17D64F60EDCDBF561195FAC8175BA9B81FE7FF000F7B761880`

## Hardware verdict

User tested the A3-S2 coherent draw-boundary raster-jitter architecture across all DLSS SR profiles used by the project:

- Custom Ultra Quality 77%
- Quality
- Balanced
- Performance
- Ultra Performance

All five modes were reported as the best temporal result so far. The scene was described as extremely steady; only ordinary low-resolution shimmer remained at Ultra Performance.

The controlled 12-frame capture bundle also verified the expected A3-S2 bridge, sign=-1 Feeder, synchronized opposite raster/DLSS jitter, and clean reset transitions.

## Architecture to preserve

A3-S2 moves raster jitter from partial `SetVertexShaderConstantF` interception to a coherent draw-boundary send of the complete c8-c11 WVP. The client-side canonical GTA state remains unjittered. Before an eligible projective scene draw, the bridge synthesizes all four WVP rows using one frame-owned Halton sample; before a non-eligible draw it restores canonical c8-c11 if necessary. The exact same bridge-owned sample is published to the Feeder before Present and consumed by DLSS SR with the proven sign inversion.

Do not alter this jitter architecture, phase count, projection math, or per-profile behavior merely for cleanup or theoretical consistency while it remains visually stable.

## Rejected experiments

A3-S2.1 and A3-S2.2 were follow-up experiments based on an incorrect assumption that Native/profile-0 required a special jitter fix. They are rejected and are NOT successors to this checkpoint.

Do not base future work on commits or binaries from S2.1/S2.2. Continue from the exact A3-S2 checkpoint above.

## Next-work rule

Future milestones must be branched from A3-S2 and should isolate one new variable at a time. Prefer read-only audits or diagnostic probes before changing the accepted temporal path. If a future change worsens UQ/Q/B/P/UP temporal stability, revert to this checkpoint immediately.
