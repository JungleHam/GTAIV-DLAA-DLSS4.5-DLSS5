@echo off
setlocal
title GTA IV FSR P1 - RESTORE PRE-TEST STATE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P1-Restore.ps1" -GameDir "%~1"
if errorlevel 1 (
  echo.
  echo RESTORE FAILED. The saved state folder was intentionally kept.
  pause
  exit /b 1
)
echo.
pause
