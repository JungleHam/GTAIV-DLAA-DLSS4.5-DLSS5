@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3G=..\m3g"
set "M2B=..\m2b"
set "OUT=%~dp0m3h-build"

if not exist "%M3G%\BUILD-M3G.bat" (
  echo [M3H] Missing %M3G%\BUILD-M3G.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3H] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce complete M3G source/binary baseline first.
call "%M3G%\BUILD-M3G.bat"
if errorlevel 1 exit /b %errorlevel%

rem Add diagnostic-only capture of the exact B-frame MV + depth resources fed to feature 11.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3H-INPUT-CAPTURE.ps1"
if errorlevel 1 exit /b %errorlevel%

rem M3H v2: install the exact-input queue call that v1 accidentally skipped because its
rem idempotence check matched the helper declaration before it reached the call site.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3H-V2.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Only Feeder changed. Rebuild it from the now-patched generated source tree.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3h.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3G%\m3g-build\OptiScaler-M3G.dll" "%OUT%\OptiScaler-M3H.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3H] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3h.addon64
echo   %OUT%\OptiScaler-M3H.dll
echo.
echo [M3H] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3h.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3H.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3H] MANUAL OBJECTIVE INPUT CAPTURE:
echo   ` = capture set 1
echo   = = capture set 2
echo.
echo   Each successful trigger saves the existing M3G A/G/B triplet PLUS:
echo     dlfg-m3h-N-modeM-MV-R16G16_FLOAT.bin
echo     dlfg-m3h-N-modeM-DEPTH-R32_FLOAT.bin
echo     dlfg-m3h-N-modeM-inputs.txt
echo.
echo   These are the exact B-frame MV/depth resources supplied to NVIDIA feature 11.
echo   No DLSS-G input values, transport, pacing, or present order are intentionally changed.
echo.
echo [M3H] Recommended first diagnostic: mode 0 baseline only.
echo   Stand still, make a steady horizontal camera pan, press ` while already moving.
echo   One clean capture is enough for the first MV-vs-optical-flow analysis.
echo.
echo [M3H] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
