@echo off
setlocal
title GTA IV FSR P1 - APPLY TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P1-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (
  echo.
  echo APPLY FAILED. Nothing should be tested until the error above is fixed.
  pause
  exit /b 1
)
echo.
pause
