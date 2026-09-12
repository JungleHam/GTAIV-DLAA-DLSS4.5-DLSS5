# Verification

The stack produces enough logs to distinguish real NGX operation from a shader that merely looks like antialiasing.

## DLAA

Open:

```text
GTAIV\.trex\dlss5-feed.log
```

A healthy base should show evidence equivalent to:

```text
DLSS5_MV_PROVIDER=3 (LumeniteFX Kernel)
feature ready: 2560x1440 DLAA ...
```

The exact resolution depends on the game output.

Healthy runtime probes should show non-trivial motion vectors and usable depth while moving through the scene.

## DLSS 5 Neural Rendering

Open:

```text
GTAIV\.trex\deep-fried-chicken.log
```

The tested successful stack showed:

```text
standalone native DLSS create ...
neural=eligible
feeder_marker=1
legacy_exact=0
feature 18: ... Success
standalone feature 18 created
standalone neural frame succeeded
```

The strongest live proof is a continuously increasing neural-frame success counter.

PowerShell live-tail example:

```powershell
Get-Content ".trex\deep-fried-chicken.log" -Tail 20 -Wait |
  Where-Object {$_ -match "neural frame succeeded|feature 18|ARMED|FAILED"}
```

If `standalone neural frame succeeded: count=...` keeps advancing, Feature 18 is actively processing frames.

## DLAA versus DLAA + NR

With the interactive ReShade patch installed:

```text
Home
 -> Deep Fried Chicken tab
 -> Enabled OFF = DLAA only
 -> Enabled ON  = DLAA + Neural Rendering
```

For a clean comparison, use the same scene and look at:

- fences and power lines;
- thin car edges;
- foliage;
- distant details;
- night lighting;
- motion stability / ghosting.

## ReShade input patch

For the original debug POC, success was:

```text
HANDSHAKE OK
HOME DOWN -> queued ReShade overlay toggle
WM_MOUSEMOVE
WM_LBUTTONDOWN
WM_RBUTTONDOWN
```

The final patch is integrated into ReShade, so normal interaction itself is the main test. ReShade's own log may also contain messages prefixed with:

```text
b-bridge input relay:
```
