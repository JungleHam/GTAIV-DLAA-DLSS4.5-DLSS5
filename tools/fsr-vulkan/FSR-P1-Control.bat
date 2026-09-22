@echo off
setlocal
set "ACTION=%~1"
if "%ACTION%"=="" set "ACTION=status"
set "GAME=%~2"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P1-Control.ps1" -Action "%ACTION%" -GameDir "%GAME%"
if errorlevel 1 (
  echo.
  echo FSR P1 controller failed.
  pause
  exit /b 1
)
echo.
pause
