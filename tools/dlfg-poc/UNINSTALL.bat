@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "GAME=%~1"
if not defined GAME (
  echo ============================================================
  echo GTA IV DLFG POC - FULL CLEANUP
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
for %%P in (GTAIV.exe NvRemixBridge.exe) do (
  tasklist /FI "IMAGENAME eq %%P" 2>nul | find /I "%%P" >nul && (
    echo ERROR: %%P is running. Fully close GTA IV first.
    pause
    exit /b 1
  )
)

echo.
echo Removing every in-game DLFG probe generation...
del /q "%TREX%\dlfg-probe.addon64" 2>nul
del /q "%TREX%\dlfg-probe.addon64.pre-poc" 2>nul
del /q "%TREX%\dlfg-probe.log" 2>nul
del /q "%TREX%\.dlfg-probe-installed" 2>nul

rem Repeated old POC installs could accidentally back up the POC's own
rem nvngx_dlssg.dll and then restore it on uninstall. Compare hashes:
rem - identical current/backup = both are the experiment runtime -> remove both
rem - different backup = treat backup as a genuine pre-existing user file -> restore it
set "CURHASH="
set "BAKHASH="
if exist "%TREX%\nvngx_dlssg.dll" (
  for /f "usebackq tokens=*" %%H in (`powershell.exe -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%TREX%\nvngx_dlssg.dll').Hash"`) do set "CURHASH=%%H"
)
if exist "%TREX%\nvngx_dlssg.dll.pre-poc" (
  for /f "usebackq tokens=*" %%H in (`powershell.exe -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%TREX%\nvngx_dlssg.dll.pre-poc').Hash"`) do set "BAKHASH=%%H"
)

if exist "%TREX%\nvngx_dlssg.dll.pre-poc" (
  if defined CURHASH if /I "%CURHASH%"=="%BAKHASH%" (
    echo Removing duplicate experimental DLSS-G runtime and stale backup...
    del /q "%TREX%\nvngx_dlssg.dll" 2>nul
    del /q "%TREX%\nvngx_dlssg.dll.pre-poc" 2>nul
  ) else (
    echo Restoring a different pre-existing nvngx_dlssg.dll backup...
    del /q "%TREX%\nvngx_dlssg.dll" 2>nul
    move /y "%TREX%\nvngx_dlssg.dll.pre-poc" "%TREX%\nvngx_dlssg.dll" >nul
  )
) else (
  rem The known-good GTA IV project stack does not install nvngx_dlssg.dll.
  rem If there is no recorded pre-POC backup, this copy came from the experiment.
  del /q "%TREX%\nvngx_dlssg.dll" 2>nul
)

echo.
if exist "%TREX%\dlfg-probe.addon64" (
  echo ERROR: dlfg-probe.addon64 is still present.
  echo Please delete it manually before launching GTA IV.
  pause
  exit /b 2
)
if exist "%TREX%\dlfg-probe.addon64.pre-poc" (
  echo ERROR: stale dlfg-probe.addon64.pre-poc is still present.
  echo Please delete it manually before launching GTA IV.
  pause
  exit /b 2
)

echo ============================================================
echo CLEANUP COMPLETE
 echo ============================================================
echo.
echo The in-game DLFG POC and stale POC backup have been removed.
echo NvRemixBridge.exe, d3d9vk_x64.dll, ReShade, Feeder and DFC were NOT touched.
echo.
echo Launch GTA IV normally once before doing any more FG testing.
echo.
pause
exit /b 0
