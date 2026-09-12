@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "GAME=%~1"
if not defined GAME (
  echo ============================================================
  echo GTA IV DLFG POC - milestone 1 installer
  echo ============================================================
  echo.
  echo Enter the GTA IV folder that contains GTAIV.exe.
  echo You can paste the path or drag the GTAIV folder into this window.
  echo.
  set /p "GAME=Game folder: "
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
if not exist "%TREX%\NvRemixBridge.exe" (
  echo ERROR: .trex\NvRemixBridge.exe was not found.
  echo Install and verify the working DLAA setup first.
  pause
  exit /b 1
)
if not exist "dlfg-probe.addon64" (
  echo ERROR: dlfg-probe.addon64 is missing.
  echo Run BUILD.bat first.
  pause
  exit /b 1
)
if not exist "nvngx_dlssg.dll" (
  echo ERROR: nvngx_dlssg.dll is missing.
  echo Run GET-RUNTIME.bat first.
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

if exist "%TREX%\dlfg-probe.addon64" (
  copy /y "%TREX%\dlfg-probe.addon64" "%TREX%\dlfg-probe.addon64.pre-poc" >nul
)
if exist "%TREX%\nvngx_dlssg.dll" if not exist "%TREX%\nvngx_dlssg.dll.pre-poc" (
  echo Preserving existing nvngx_dlssg.dll...
  copy /y "%TREX%\nvngx_dlssg.dll" "%TREX%\nvngx_dlssg.dll.pre-poc" >nul || goto :fail
)

copy /y "dlfg-probe.addon64" "%TREX%\dlfg-probe.addon64" >nul || goto :fail
copy /y "nvngx_dlssg.dll" "%TREX%\nvngx_dlssg.dll" >nul || goto :fail
del /q "%TREX%\dlfg-probe.log" 2>nul
>"%TREX%\.dlfg-probe-installed" echo milestone1

echo.
echo ============================================================
echo INSTALLED - SAFE PROBE ONLY
 echo ============================================================
echo.
echo This POC does NOT generate or present frames yet.
echo It creates a PRIVATE Vulkan device and asks NVIDIA NGX to create a DLSS-G feature.
echo.
echo Next:
echo   1. For the first test, use DLAA and turn DFC neural processing OFF if convenient.
echo   2. Launch GTA IV and wait about 5 seconds in a rendered scene.
echo   3. Close GTA IV.
echo   4. Send this file:
echo.
echo      "%TREX%\dlfg-probe.log"
echo.
echo The line we want is:
echo   SUCCESS: NVIDIA NGX DLSS Frame Generation feature was created on the RTX GPU.
echo.
echo To remove the POC, run UNINSTALL.bat.
echo.
pause
exit /b 0

:fail
echo.
echo INSTALL FAILED. No existing backup files were intentionally removed.
pause
exit /b 1
