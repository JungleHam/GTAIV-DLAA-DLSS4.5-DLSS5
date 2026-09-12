# ReShade b-bridge input patch

See [`../../docs/RESHade-INPUT-PATCH.md`](../../docs/RESHade-INPUT-PATCH.md) for the design and full instructions.

Quick usage:

```text
BUILD.bat
```

then from an Administrator terminal:

```text
INSTALL.bat "X:\path\to\Grand Theft Auto IV\GTAIV"
```

Rollback:

```text
RESTORE_ORIGINAL.bat "X:\path\to\Grand Theft Auto IV\GTAIV"
```

The build output `ReShade64-bbridge.dll` and cloned `reshade-src/` tree are ignored by Git.
