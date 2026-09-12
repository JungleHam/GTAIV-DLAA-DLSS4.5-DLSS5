@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "URL=https://github.com/NVIDIAGameWorks/rtx-remix/releases/download/remix-1.5.2/remix-1.5.2-release.zip"
set "EXPECTED=cc424be4dd1a0c6fd922bc6a7f8e5f6582baea7043a38afa6686d8b6faabad01"
set "ZIP=%TEMP%\gtaiv-dlfg-remix-1.5.2-release.zip"
set "OUT=%TEMP%\gtaiv-dlfg-remix-1.5.2"

echo ============================================================
echo GTA IV DLFG POC - get NVIDIA DLSS Frame Generation runtime
echo ============================================================
echo.
echo This downloads the official NVIDIA RTX Remix 1.5.2 release archive
echo (about 230 MB) and extracts ONLY nvngx_dlssg.dll for this experiment.
echo The full RTX Remix renderer is NOT installed into GTA IV.
echo.

if exist "nvngx_dlssg.dll" (
  echo nvngx_dlssg.dll is already present next to this script.
  pause
  exit /b 0
)

echo Downloading official NVIDIA RTX Remix package...
where curl.exe >nul 2>nul
if not errorlevel 1 (
  curl.exe -L --fail --retry 3 -o "%ZIP%" "%URL%" || goto :fail
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%ZIP%'" || goto :fail
)

echo Verifying SHA256...
set "GOT="
for /f "usebackq tokens=*" %%H in (`powershell.exe -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%ZIP%').Hash.ToLowerInvariant()"`) do set "GOT=%%H"
if /I not "%GOT%"=="%EXPECTED%" (
  echo ERROR: RTX Remix archive hash mismatch.
  echo Expected: %EXPECTED%
  echo Got:      %GOT%
  goto :fail
)

echo Extracting archive...
if exist "%OUT%" rmdir /s /q "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%OUT%' -Force" || goto :fail

echo Locating 64-bit nvngx_dlssg.dll...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$f=Get-ChildItem -LiteralPath '%OUT%' -Recurse -File -Filter 'nvngx_dlssg.dll' ^| Sort-Object Length -Descending ^| Select-Object -First 1; if(!$f){exit 3}; Copy-Item -LiteralPath $f.FullName -Destination '%CD%\nvngx_dlssg.dll' -Force; Write-Host ('Source: '+$f.FullName); Write-Host ('Size: '+$f.Length)" || goto :fail

if not exist "nvngx_dlssg.dll" goto :fail

echo Cleaning temporary RTX Remix archive...
del /q "%ZIP%" 2>nul
rmdir /s /q "%OUT%" 2>nul

echo.
echo SUCCESS: %CD%\nvngx_dlssg.dll
echo.
echo This file came from NVIDIA's official RTX Remix 1.5.2 release package.
echo Next: run INSTALL.bat.
echo.
pause
exit /b 0

:fail
echo.
echo FAILED. The game installation has not been changed.
echo Temporary files may remain under %%TEMP%% and can be deleted safely.
pause
exit /b 1
