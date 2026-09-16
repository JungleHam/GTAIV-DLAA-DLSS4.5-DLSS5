# ReShade b-bridge input patch

See [`../../docs/RESHade-INPUT-PATCH.md`](../../docs/RESHade-INPUT-PATCH.md) for the design and full instructions.

## Install

1. Double-click **`BUILD.bat`** and wait for `BUILD SUCCESS - PATCH MARKER VERIFIED`.
2. Close the build window.
3. **Right-click `INSTALL.bat` -> Run as administrator.**
4. Paste or drag in the GTA IV folder containing `GTAIV.exe`, then press Enter.
5. Launch GTA IV and wait for a rendered menu/gameplay scene.
6. Press **Home**.

> File installation alone is not proof. Step 3 is complete only when Home opens the ReShade overlay and mouse/keyboard input works inside it.

If Home does nothing, troubleshoot before continuing to the combined DLSS 4.5 SR + DLSS 5 NR module.

Useful files:

```text
GTAIV\.trex\bridge.conf
GTAIV\.trex\ReShade.log
```

## Rollback

Double-click **`RESTORE_ORIGINAL.bat`**, enter the same GTA IV folder, and approve UAC when Windows asks.

The build output `ReShade64-bbridge.dll` and cloned `reshade-src/` tree are ignored by Git.
