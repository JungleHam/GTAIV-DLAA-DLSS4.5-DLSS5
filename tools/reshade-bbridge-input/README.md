# ReShade b-bridge input patch

See [`../../docs/RESHade-INPUT-PATCH.md`](../../docs/RESHade-INPUT-PATCH.md) for the design and full instructions.

## Easy install

No terminal commands are required for the normal flow:

1. Double-click **`BUILD.bat`** and wait for `SUCCESS`.
2. Double-click **`INSTALL.bat`**.
3. Paste or drag in the GTA IV folder that contains `GTAIV.exe`, then press Enter.
4. Windows asks for Administrator/UAC permission — click **Yes**.
5. Launch GTA IV and press **Home**.

The path is requested before elevation so normal Explorer drag-and-drop works.

## Rollback

Double-click **`RESTORE_ORIGINAL.bat`**, enter the same GTA IV folder, then approve UAC when Windows asks.

The build output `ReShade64-bbridge.dll` and cloned `reshade-src/` tree are ignored by Git.
