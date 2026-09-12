@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "GAME=%~1"
if not defined GAME (
  echo ============================================================
  echo GTA IV DLFG POC - uninstall
  echo ============================================================
  echo.
  set /p "GAME=Game folder containing GTAIV.exe: "
)

if not defined GAME exit /b 1
set "GAME=%GAME:"=%"
for %%I in ("%GAME%") do if /I "%%~nxI"=="GTAIV.exe" set "GAME=%%~dpI"
if not exist "%GAME%\GTAIV.exe" if exist "%GAME%\GTAIV\GTAIV.exe" set "GAME=%GAME%\GTAIV"
if not exist "%GAME%\GTAIV.exe" (
  echo ERROR: GTAIV.exe was not found there.
  pause
  exit /b 1
)

set "TREX=%GAME%\.trex"
for %%P in (GTAIV.exe NvRemixBridge.exe) do (
  tasklist /FI "IMAGENAME eq %%P" 2>nul | find /I "%%P" >nul && (
    echo ERROR: %%P is running. Fully close GTA IV first.
    pause
    exit /b 1
  )
)

del /q "%TREX%\dlfg-probe.addon64" 2>nul
del /q "%TREX%\dlfg-probe.log" 2>nul
del /q "%TREX%\.dlfg-probe-installed" 2>nul

if exist "%TREX%\dlfg-probe.addon64.pre-poc" (
  move /y "%TREX%\dlfg-probe.addon64.pre-poc" "%TREX%\dlfg-probe.addon64" >nul
)
if exist "%TREX%\nvngx_dlssg.dll.pre-poc" (
  del /q "%TREX%\nvngx_dlssg.dll" 2>nul
  move /y "%TREX%\nvngx_dlssg.dll.pre-poc" "%TREX%\nvngx_dlssg.dll" >nul
) else (
  del /q "%TREX%\nvngx_dlssg.dll" 2>nul
)

echo.
echo DLFG milestone-1 POC removed. The normal DLAA/DLSS5 stack was not changed.
pause
