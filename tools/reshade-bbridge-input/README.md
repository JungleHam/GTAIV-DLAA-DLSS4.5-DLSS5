# ReShade b-bridge input patch

See [`../../docs/RESHade-INPUT-PATCH.md`](../../docs/RESHade-INPUT-PATCH.md) for the design and full instructions.

## Easy install

No terminal commands are required for the normal flow:

1. Double-click **`BUILD.bat`** and wait for `SUCCESS`.
2. Double-click **`INSTALL.bat`**.
3. Paste or drag in the GTA IV folder that contains `GTAIV.exe`, then press Enter.
4. Windows asks for Administrator/UAC permission — click **Yes**.
5. Fully launch GTA IV again and wait until a rendered menu or gameplay scene appears.
6. Press **Home**.

The path is requested before elevation so normal Explorer drag-and-drop works.

> **Important:** file installation alone does not prove the input patch is working. Step 3 is only verified when **Home actually opens the ReShade overlay and mouse/keyboard input works inside it**. If Home does nothing, stop there and troubleshoot before continuing to the DLSS 5 step.

Useful troubleshooting files:

```text
GTAIV\.trex\bridge.conf
GTAIV\.trex\ReShade.log
```

## Rollback

Double-click **`RESTORE_ORIGINAL.bat`**, enter the same GTA IV folder, then approve UAC when Windows asks.

The build output `ReShade64-bbridge.dll` and cloned `reshade-src/` tree are ignored by Git.
