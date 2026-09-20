# ReShade 6.8.0 b-bridge cross-process input patch

## Problem

In this stack:

```text
GTAIV.exe owns the game HWND
NvRemixBridge.exe runs Vulkan + ReShade
```

The ReShade overlay can render correctly, but stock ReShade refuses normal input capture because the target HWND belongs to another process.

## Discovery

b-bridge's GTA-side client already forwards DirectInput state as ordinary Windows messages and retains the old Remix registration/UI-active message channel.

The debug POC under `tools/debug/bridge-input-poc/` proved the transport:

```text
GTA IV
 -> b-bridge x86
 -> cross-process message channel
 -> NvRemixBridge x64
```

including Home, mouse movement, clicks and keyboard messages.

## Final patch

`apply_patch.ps1` makes targeted changes to the exact ReShade 6.8.0 source.

### `source/input_windows.cpp`

It:

- accepts the foreign GTA HWND;
- starts a message-queue worker;
- registers with b-bridge through `UWM_REMIX_BRIDGE_REGISTER_THREADPROC_MSG`;
- reconstructs the forwarded HWND/message context;
- routes events through ReShade's normal `input::handle_window_message` path.

### `source/runtime_gui.cpp`

When the ReShade overlay opens/closes, the patch sends:

```text
UWM_REMIX_UIACTIVE_MSG
```

back to GTA's b-bridge client so the game does not also consume overlay input.

## Build

Requirements:

- Git for Windows;
- Python 3 in `PATH`;
- Visual Studio 2022 / Build Tools;
- Desktop development with C++.

Normal flow:

1. Double-click **`BUILD.bat`**.
2. Wait for `BUILD SUCCESS - PATCH MARKER VERIFIED`.
3. Close the build window.

The build clones exact ReShade `v6.8.0`, applies the patch idempotently and produces:

```text
ReShade64-bbridge.dll
```

## Install

Fully close GTA IV and `NvRemixBridge.exe`.

For the current reliable install path:

1. **Right-click `INSTALL.bat` -> Run as administrator.**
2. Paste or drag the GTA IV folder containing `GTAIV.exe` into the installer.
3. Press Enter.
4. Let the installer back up and replace the global ReShade Vulkan DLL.

Example:

```text
B:\Games\Steam\steamapps\common\Grand Theft Auto IV\GTAIV
```

The installer backs up:

```text
C:\ProgramData\ReShade\ReShade64\ReShade64.dll
```

to:

```text
C:\ProgramData\ReShade\ReShade64\ReShade64.dll.pre-bbridge-input
```

It also writes these b-bridge policies where possible:

```ini
client.DirectInput.forward.mousePolicy = 3
client.DirectInput.forward.keyboardPolicy = 3
```

## Verify before Step 4

File installation alone does not prove the patch works.

After installation:

1. launch GTA IV;
2. wait for a rendered menu/gameplay scene;
3. press **Home**.

Step 3 is successful only if:

- Home opens/closes ReShade;
- the ReShade cursor moves;
- tabs, checkboxes and sliders can be clicked;
- keyboard input works inside the overlay;
- the DLSS5-Feeder controls are interactive;
- closing the overlay returns control to GTA.

If Home does nothing, stop and troubleshoot before installing the combined DLSS 4.5 SR + DLSS 5 NR module.

Useful files:

```text
GTAIV\.trex\bridge.conf
GTAIV\.trex\ReShade.log
```

Expected patched-log evidence may include:

```text
b-bridge input relay: accepting foreign render window
b-bridge input relay: handshake complete
```

## Restore stock ReShade

Close GTA IV and `NvRemixBridge.exe`, then run:

```text
RESTORE_ORIGINAL.bat
```

Use the same GTA IV folder when prompted.

## Scope

The patch is pinned to ReShade 6.8.0 and should be reviewed/rebased before use with another ReShade release.

It does not provide DLAA, SR or NR by itself. It only restores interactive ReShade input across the b-bridge process boundary.
