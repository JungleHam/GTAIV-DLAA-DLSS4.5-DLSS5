@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3B2B=..\m3b2b"
set "M2B=..\m2b"
set "OUT=%~dp0m3c-build"

if not exist "%M3B2B%\BUILD-M3B2B.bat" (
  echo [M3C] Missing %M3B2B%\BUILD-M3B2B.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3C] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)
if not exist "%~dp0APPLY-M3C-RING.ps1" (
  echo [M3C] Missing APPLY-M3C-RING.ps1
  exit /b 1
)

rem Reproduce the exact hardware-proven M3B-2B source/binaries first.
call "%M3B2B%\BUILD-M3B2B.bat"
if errorlevel 1 exit /b %errorlevel%

rem Patch the freshly regenerated M3B-2A ring with newline-safe M3C FIFO semantics first.
rem APPLY-M3C-QUEUE.ps1 then sees the integration marker and only layers the config/main-source changes.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3C-RING.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Layer ONLY the default-off M3C config/main-source integration on top of proven M3B-2B.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3C-QUEUE.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Rebuild the generated/patched Feeder source tree. OptiScaler remains byte-for-byte
rem the already-proven M3B-2B/M3B-2A consumer.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3c.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3B2B%\m3b2b-build\OptiScaler-M3B2B.dll" "%OUT%\OptiScaler-M3C.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3C] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3c.addon64
echo   %OUT%\OptiScaler-M3C.dll
echo.
echo [M3C] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3c.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3C.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3C] TEST MODE:
echo   dlfg_m3b2b_native=1
echo   dlfg_m3c_queue=1
echo   Keep FusionFix Windowed = On and Windowed Borderless = On.
echo   Do NOT press Alt+Enter and do NOT switch Windowed Off.
echo.
echo [M3C] TARGET:
echo   MILESTONE M3C PRODUCER PASSED = 300 consecutive publications with sourceFrame delta=1
echo   OptiScaler consumer should also remain consecutive with no present/consumer-done failures.
endlocal
