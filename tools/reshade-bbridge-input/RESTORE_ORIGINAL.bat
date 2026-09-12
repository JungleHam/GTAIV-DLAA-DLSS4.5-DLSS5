@echo off
setlocal EnableExtensions
set "RESHADESYS=C:\ProgramData\ReShade\ReShade64.dll"
set "BACKUP=C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input"

if "%~1"=="" (
  echo Usage:
  echo   RESTORE_ORIGINAL.bat "X:\path\to\Grand Theft Auto IV\GTAIV"
  pause
  exit /b 1
)
set "GAME=%~1"
set "TREX=%GAME%\.trex"
set "POC=%TREX%\bridge-input.addon64"
set "POCDISABLED=%TREX%\bridge-input.addon64.poc-disabled"

net session >nul 2>nul
if errorlevel 1 (
  echo ERROR: Run this script from an elevated Command Prompt/Terminal.
  pause
  exit /b 1
)

for %%P in (GTAIV.exe NvRemixBridge.exe) do (
  tasklist /FI "IMAGENAME eq %%P" 2>nul | find /I "%%P" >nul && (
    echo ERROR: %%P is running. Fully close GTA IV first.
    pause
    exit /b 1
  )
)

if not exist "%BACKUP%" (
  echo ERROR: Backup not found:
  echo   %BACKUP%
  pause
  exit /b 1
)

copy /y "%BACKUP%" "%RESHADESYS%" >nul || (
  echo ERROR: Could not restore ReShade64.dll.
  pause
  exit /b 1
)

if exist "%POCDISABLED%" if not exist "%POC%" ren "%POCDISABLED%" "bridge-input.addon64"

echo Original ReShade64.dll restored.
pause
