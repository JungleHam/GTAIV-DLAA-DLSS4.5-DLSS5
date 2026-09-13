@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3F=..\m3f"
set "M2B=..\m2b"
set "OUT=%~dp0m3g-build"

if not exist "%M3F%\BUILD-M3F.bat" (
  echo [M3G] Missing %M3F%\BUILD-M3F.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3G] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the complete M3F source/binary baseline first.
call "%M3F%\BUILD-M3F.bat"
if errorlevel 1 exit /b %errorlevel%

rem Add manual runtime export of a clean continuous-native A/G/B triplet.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3G-TRIPLET-CAPTURE.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Only Feeder changed. OptiScaler remains byte-identical to M3F.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3g.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3F%\m3f-build\OptiScaler-M3F.dll" "%OUT%\OptiScaler-M3G.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3G] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3g.addon64
echo   %OUT%\OptiScaler-M3G.dll
echo.
echo [M3G] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3g.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3G.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3G] MANUAL OBJECTIVE CAPTURE:
echo   Page Up   = capture set 1
 echo   Page Down = capture set 2
 echo.
echo   Each key captures the next clean continuous-native triplet:
echo     A = real frame
 echo     G = NVIDIA feature-11 generated midpoint
 echo     B = next sequential real frame
 echo.
echo   Filenames are written next to the live Feeder addon and include the active M3F MV mode,
echo   for example: dlfg-m3g-1-mode0-A-prev-real.bmp
 echo.
echo   Recommended first run: M3F mode 0 baseline, steady horizontal camera pan, press Page Up.
echo   A second in-game comparison can use another M3F mode, then press Page Down.
echo.
echo [M3G] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
