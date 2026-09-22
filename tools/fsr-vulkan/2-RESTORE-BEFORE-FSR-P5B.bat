@echo off
setlocal
title GTA IV FSR P5B - RESTORE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P5B-Restore.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo RESTORE FAILED; saved state kept.&pause&exit /b 1)
echo.&pause
