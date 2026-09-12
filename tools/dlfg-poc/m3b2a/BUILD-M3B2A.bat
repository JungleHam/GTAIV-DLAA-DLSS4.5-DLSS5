@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M2B=..\m2b"
set "M3A=..\m3a-os"
set "OUT=%~dp0m3b2a-build"

if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3B-2A] Missing %M2B%\BUILD-M2B-PROBE.bat
  echo Run the existing M2B setup/build once in this checkout first.
  exit /b 1
)
if not exist "%M3A%\BUILD-M3A-OS.bat" (
  echo [M3B-2A] Missing %M3A%\BUILD-M3A-OS.bat
  echo Run the existing M3A-OS setup/build once in this checkout first.
  exit /b 1
)

rem Prepare/build the pinned Feeder tree, preserve the known-good M3B-1 loading fix,
rem then layer the M3B-2A reusable transport on top.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%
powershell -NoProfile -ExecutionPolicy Bypass -File "%M2B%\APPLY-M3B1-LOADING-RETRY.ps1"
if errorlevel 1 exit /b %errorlevel%
powershell -NoProfile -ExecutionPolicy Bypass -File "%M2B%\APPLY-M3B2A-FEEDER.ps1"
if errorlevel 1 exit /b %errorlevel%
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

rem Prepare/build the pinned OptiScaler tree, then layer the M3B-2A consumer on top.
call "%M3A%\BUILD-M3A-OS.bat"
if errorlevel 1 exit /b %errorlevel%
powershell -NoProfile -ExecutionPolicy Bypass -File "%M3A%\APPLY-M3B2A-OPTISCALER.ps1"
if errorlevel 1 exit /b %errorlevel%
call "%M3A%\BUILD-M3A-OS.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3b2a.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3A%\m3a-build\OptiScaler-M3A-OS.dll" "%OUT%\OptiScaler-M3B2A.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3B-2A] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3b2a.addon64
echo   %OUT%\OptiScaler-M3B2A.dll
echo.
echo [M3B-2A] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3b2a.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3B2A.dll" SHA256 | findstr /R /V "hash CertUtil"
endlocal
