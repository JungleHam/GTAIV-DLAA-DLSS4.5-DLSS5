# Original bridge-input proof of concept

This is the isolated ReShade add-on used to prove that b-bridge already forwards GTA IV keyboard/mouse events across its dormant RTX Remix message channel into `NvRemixBridge.exe`.

It does **not** provide the final clickable ReShade UI. The final solution is the ReShade source patch in `tools/reshade-bbridge-input/`.

Expected proof path:

```text
GTA input
 -> b-bridge x86 DirectInput hook
 -> PostThreadMessage
 -> bridge-input.addon64 in NvRemixBridge.exe
```

A successful test log contained lines such as:

```text
HANDSHAKE OK
HOME DOWN -> queued ReShade overlay toggle
WM_KEYDOWN
WM_MOUSEMOVE
WM_LBUTTONDOWN
WM_RBUTTONDOWN
```

The POC also toggles ReShade's public `effect_runtime::open_overlay()` API with Home and sends `UWM_REMIX_UIACTIVE_MSG` back to the GTA-side bridge.

## Build

Run `build.bat`. It clones ReShade 6.8.0 for headers and builds an x64 ReShade add-on.

## Historical config

See `bridge.conf-snippet.txt`.

Do not install this POC at the same time as the final patched ReShade build; both would try to own the same bridge input channel.
