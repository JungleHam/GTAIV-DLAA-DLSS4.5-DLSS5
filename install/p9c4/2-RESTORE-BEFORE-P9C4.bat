@echo off
setlocal
title GTA IV P9C.4 - RESTORE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P9C4-Restore.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo RESTORE FAILED; saved state kept.&pause&exit /b 1)
echo.
pause
