# ReShade 6.8.0 b-bridge cross-process input patch

## Problem

In this stack:

```text
GTAIV.exe owns the game HWND
NvRemixBridge.exe runs Vulkan + ReShade
```

The ReShade overlay is rendered correctly, but stock ReShade refuses normal input capture because the target HWND belongs to another process.

That is why the server-side ReShade UI can be visible but cannot normally be clicked.

## Discovery

b-bridge's GTA-side client already contains a DirectInput forwarder. It translates GTA input into ordinary Windows messages:

```text
WM_KEYDOWN / WM_KEYUP / WM_CHAR
WM_MOUSEMOVE
WM_LBUTTONDOWN / UP
WM_RBUTTONDOWN / UP
WM_MOUSEWHEEL
...
```

It also retains the RTX Remix renderer registration message:

```text
UWM_REMIX_BRIDGE_REGISTER_THREADPROC_MSG
```

and UI-state message:

```text
UWM_REMIX_UIACTIVE_MSG
```

The missing piece in the non-RTX-DXVK b-bridge path was a renderer-side consumer.

The debug POC under `tools/debug/bridge-input-poc/` proved the complete transport:

```text
GTA IV
 -> b-bridge x86
 -> cross-process message channel
 -> NvRemixBridge x64
```

including Home, mouse moves, left/right clicks and keyboard messages.

## Final patch

`apply_patch.ps1` makes two targeted changes to the exact ReShade 6.8.0 source.

### `source/input_windows.cpp`

It:

- accepts the foreign GTA HWND instead of returning `nullptr`;
- starts a message-queue worker;
- registers itself with b-bridge through `UWM_REMIX_BRIDGE_REGISTER_THREADPROC_MSG`;
- reconstructs the foreign HWND on forwarded thread messages;
- forwards those messages into ReShade's existing `input::handle_window_message` path.

This deliberately uses ReShade's **normal input system** rather than maintaining a separate ImGui implementation.

### `source/runtime_gui.cpp`

When the ReShade overlay opens or closes, the patch sends:

```text
UWM_REMIX_UIACTIVE_MSG
```

back to GTA's b-bridge client.

b-bridge can then use its existing UI-active behavior to swallow clicks/keys before the game also reacts to them.

## Build

Requirements:

- Git
- Python in PATH
- Visual Studio 2022 or Build Tools
- `Desktop development with C++`

No terminal knowledge is required for the normal install flow.

1. **Double-click `BUILD.bat`.**
2. Wait for it to say `SUCCESS` and create `ReShade64-bbridge.dll`.
3. Close the build window.

`BUILD.bat` clones exact ReShade `v6.8.0` with submodules, applies the patch idempotently, and builds:

```text
ReShade64-bbridge.dll
```

## Install

First fully close GTA IV and `NvRemixBridge.exe`.

Then simply **double-click `INSTALL.bat`**.

The installer now handles the rest itself:

1. Windows shows a User Account Control prompt — click **Yes**.
2. The installer asks for your GTA IV folder.
3. Copy/paste the folder path, or drag the folder into the installer window, then press **Enter**.

Example path:

```text
B:\Games\Steam\steamapps\common\Grand Theft Auto IV\GTAIV
```

The script is deliberately forgiving: if you paste `GTAIV.exe` itself, or select the outer `Grand Theft Auto IV` folder, it tries to resolve the correct `GTAIV` folder automatically.

The script backs up:

```text
C:\ProgramData\ReShade\ReShade64.dll
```

to:

```text
C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input
```

and installs the patched DLL.

It also writes these b-bridge policies if possible:

```ini
client.DirectInput.forward.mousePolicy = 3
client.DirectInput.forward.keyboardPolicy = 3
```

## Expected result

Launch GTA IV and press Home.

You should be able to:

- open/close ReShade with Home;
- move the ReShade cursor;
- click tabs, checkboxes and sliders;
- operate the DLSS5-Feeder preset selector and Deep Fried Chicken live;
- return control to GTA when the overlay closes.

## Restore stock ReShade

Close GTA IV and `NvRemixBridge.exe`, then simply **double-click `RESTORE_ORIGINAL.bat`**.

It requests Administrator permission itself and asks for the GTA IV folder in the same way as the installer. No terminal command is required.

## Scope

The patch is intentionally pinned to ReShade 6.8.0. It should be reviewed/rebased before using it against another ReShade release.

It does not modify DFC, Feeder, LumeniteFX, FusionFix, DXVK or b-bridge binaries.
