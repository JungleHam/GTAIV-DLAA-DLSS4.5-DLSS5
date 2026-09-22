@echo off
setlocal
title GTA IV FSR P2 - APPLY TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P2-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (
  echo.
  echo APPLY FAILED. The helper attempted automatic rollback.
  pause
  exit /b 1
)
echo.
pause
