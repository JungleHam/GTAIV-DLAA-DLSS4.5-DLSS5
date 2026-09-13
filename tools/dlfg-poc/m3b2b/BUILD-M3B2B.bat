@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3B2A=..\m3b2a"
set "M2B=..\m2b"
set "OUT=%~dp0m3b2b-build"

if not exist "%M3B2A%\BUILD-M3B2A.bat" (
  echo [M3B-2B] Missing %M3B2A%\BUILD-M3B2A.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3B-2B] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem First reproduce the exact M3B-2A source/binaries that passed the hardware test.
call "%M3B2A%\BUILD-M3B2A.bat"
if errorlevel 1 exit /b %errorlevel%

rem Layer ONLY the M3B-2B native Feeder producer on top. OptiScaler's proven M3B-2A
rem consumer is intentionally unchanged.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3B2B-FEEDER.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Rebuild the already-generated/patched Feeder source tree.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3b2b.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3B2A%\m3b2a-build\OptiScaler-M3B2A.dll" "%OUT%\OptiScaler-M3B2B.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3B-2B] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3b2b.addon64
echo   %OUT%\OptiScaler-M3B2B.dll
echo.
echo [M3B-2B] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3b2b.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3B2B.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3B-2B] IMPORTANT HARDWARE-TEST LIMIT:
echo   Keep FusionFix Windowed = On and Windowed Borderless = On.
echo   Do NOT press Alt+Enter and do NOT switch Windowed Off during this milestone.
echo   The fullscreen/exclusive transition is a separately confirmed crash path.
endlocal
