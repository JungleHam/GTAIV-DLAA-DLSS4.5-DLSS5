# ReShade b-bridge input patch

See [`../../docs/RESHade-INPUT-PATCH.md`](../../docs/RESHade-INPUT-PATCH.md) for the design and full instructions.

## Easy install

No terminal commands are required for the normal flow:

1. Double-click **`BUILD.bat`** and wait for `SUCCESS`.
2. Double-click **`INSTALL.bat`**.
3. Approve the Windows Administrator/UAC prompt.
4. Paste or drag in the GTA IV folder that contains `GTAIV.exe`, then press Enter.
5. Launch GTA IV and press **Home**.

The installer also accepts the game path as a command-line argument for advanced users, but that is optional.

## Rollback

Double-click **`RESTORE_ORIGINAL.bat`**, approve UAC, and enter the same GTA IV folder when asked.

The build output `ReShade64-bbridge.dll` and cloned `reshade-src/` tree are ignored by Git.
