@echo off
setlocal
title GTA IV P9B.1 - RESTORE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P9B1-Restore.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo RESTORE FAILED; saved state kept.&pause&exit /b 1)
echo.&pause
