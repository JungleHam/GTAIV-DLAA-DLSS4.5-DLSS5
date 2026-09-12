@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "BB_SELF=%~f0"
set "RESHADESYS=C:\ProgramData\ReShade\ReShade64.dll"
set "BACKUP=C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input"

rem Ask for the game first so paste/drag works in a normal non-elevated window.
set "GAME=%~1"
if not defined GAME (
  echo ============================================================
  echo Restore original ReShade Vulkan DLL
  echo ============================================================
  echo.
  echo Please enter the GTA IV game folder that contains GTAIV.exe.
  echo You can COPY/PASTE the path, or DRAG THE GTAIV FOLDER into this window.
  echo.
  echo Example:
  echo   B:\Games\Steam\steamapps\common\Grand Theft Auto IV\GTAIV
  echo.
  set /p "GAME=Game folder: "
)

if not defined GAME (
  echo.
  echo ERROR: No game folder was entered.
  pause
  exit /b 1
)

set "GAME=%GAME:"=%"
for %%I in ("%GAME%") do if /I "%%~nxI"=="GTAIV.exe" set "GAME=%%~dpI"
if not exist "%GAME%\GTAIV.exe" if exist "%GAME%\GTAIV\GTAIV.exe" set "GAME=%GAME%\GTAIV"

if not exist "%GAME%\GTAIV.exe" (
  echo.
  echo ERROR: GTAIV.exe was not found there.
  echo Make sure you entered the folder that actually contains GTAIV.exe.
  pause
  exit /b 1
)

rem Request UAC automatically and preserve the selected game folder.
net session >nul 2>nul
if errorlevel 1 (
  set "BB_GAME=%GAME%"
  echo.
  echo Windows will now ask for Administrator permission.
  echo Click Yes to restore the original ReShade Vulkan DLL.
  echo.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$arg='\"'+$env:BB_GAME+'\"'; Start-Process -FilePath $env:BB_SELF -ArgumentList $arg -Verb RunAs" || (
    echo ERROR: Could not request Administrator permission.
    pause
    exit /b 1
  )
  exit /b 0
)

set "TREX=%GAME%\.trex"
set "POC=%TREX%\bridge-input.addon64"
set "POCDISABLED=%TREX%\bridge-input.addon64.poc-disabled"

echo.
echo Using game folder:
echo   "%GAME%"
echo.

for %%P in (GTAIV.exe NvRemixBridge.exe) do (
  tasklist /FI "IMAGENAME eq %%P" 2>nul | find /I "%%P" >nul && (
    echo ERROR: %%P is running. Fully close GTA IV first.
    pause
    exit /b 1
  )
)

if not exist "%BACKUP%" (
  echo ERROR: Backup not found:
  echo   "%BACKUP%"
  echo.
  echo Nothing was changed.
  pause
  exit /b 1
)

copy /y "%BACKUP%" "%RESHADESYS%" >nul || (
  echo ERROR: Could not restore ReShade64.dll.
  echo Another Vulkan/ReShade application may still have it loaded.
  pause
  exit /b 1
)

if exist "%POCDISABLED%" if not exist "%POC%" ren "%POCDISABLED%" "bridge-input.addon64"

echo.
echo ============================================================
echo ORIGINAL RESHADE RESTORED SUCCESSFULLY
echo ============================================================
echo.
pause
