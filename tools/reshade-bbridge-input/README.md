# ReShade b-bridge input patch

See [`../../docs/RESHade-INPUT-PATCH.md`](../../docs/RESHade-INPUT-PATCH.md) for the design and full instructions.

> **PowerShell note:** PowerShell does not execute files from the current directory unless you prefix them with `./` or `.\`. The examples below use `.\` so they work directly in PowerShell.

Quick usage:

```powershell
.\BUILD.bat
```

then from an Administrator terminal:

```powershell
.\INSTALL.bat "X:\path\to\Grand Theft Auto IV\GTAIV"
```

Rollback:

```powershell
.\RESTORE_ORIGINAL.bat "X:\path\to\Grand Theft Auto IV\GTAIV"
```

The build output `ReShade64-bbridge.dll` and cloned `reshade-src/` tree are ignored by Git.
