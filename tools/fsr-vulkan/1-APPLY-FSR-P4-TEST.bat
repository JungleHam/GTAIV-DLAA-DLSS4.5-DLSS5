@echo off
setlocal
title GTA IV FSR P4 - APPLY TEMPORAL TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P4-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (
  echo.
  echo APPLY FAILED. The helper attempted automatic rollback.
  pause
  exit /b 1
)
echo.
pause
