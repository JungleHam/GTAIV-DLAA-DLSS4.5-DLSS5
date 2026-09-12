@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo GTA IV DLFG milestone 1.2 - SAFE STANDALONE PROBE
echo ============================================================
echo.
echo This DOES NOT load into GTA IV.
echo Close GTA IV before running it.
echo.

for %%P in (GTAIV.exe NvRemixBridge.exe) do (
  tasklist /FI "IMAGENAME eq %%P" 2>nul | find /I "%%P" >nul && (
    echo ERROR: %%P is already running.
    echo Fully close GTA IV first, then run this again.
    pause
    exit /b 1
  )
)

if not exist "standalone\NvRemixBridge.exe" (
  echo ERROR: standalone\NvRemixBridge.exe is missing.
  echo Download the latest milestone 1.2 artifact or build it first.
  pause
  exit /b 1
)

if not exist "nvngx_dlssg.dll" (
  echo ERROR: nvngx_dlssg.dll is missing next to this script.
  echo Run GET-RUNTIME.bat first.
  pause
  exit /b 1
)

copy /y "nvngx_dlssg.dll" "standalone\nvngx_dlssg.dll" >nul || (
  echo ERROR: Could not copy nvngx_dlssg.dll into standalone folder.
  pause
  exit /b 1
)

del /q "standalone\dlfg-standalone.log" "standalone\dlfg-generated.bmp" 2>nul

echo Running isolated probe...
pushd "standalone"
"NvRemixBridge.exe"
set "RC=%ERRORLEVEL%"
popd

echo.
echo Probe exit code: %RC%
echo Log:
echo   %CD%\standalone\dlfg-standalone.log
echo.
if exist "standalone\dlfg-standalone.log" (
  type "standalone\dlfg-standalone.log"
) else (
  echo ERROR: no log was created.
)
if "%RC%"=="0" if exist "standalone\dlfg-generated.bmp" (
  echo.
  echo SUCCESS: generated image:
  echo   %CD%\standalone\dlfg-generated.bmp
)
echo.
pause
exit /b %RC%
