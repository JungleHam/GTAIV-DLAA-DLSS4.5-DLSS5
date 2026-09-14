@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3IA=..\m3i"
set "M2B=..\m2b"
set "OUT=%~dp0m3i-b-build"

if not exist "%M3IA%\BUILD-M3I-A.bat" (
  echo [M3I-B] Missing %M3IA%\BUILD-M3I-A.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-B] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the complete M3I-A baseline first. This recreates M3H/M3G/M3F
rem and then adds the zero-behaviour-change resolution audit.
call "%M3IA%\BUILD-M3I-A.bat"
if errorlevel 1 exit /b %errorlevel%

rem Change one DLSS-G metadata bit only: full-resolution MVs are declared already dilated.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-B-MV-DILATED.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Only Feeder source changed. Rebuild it from the patched generated source tree.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3i-b.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3IA%\m3i-build\OptiScaler-M3I-A.dll" "%OUT%\OptiScaler-M3I-B.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3I-B] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3i-b.addon64
echo   %OUT%\OptiScaler-M3I-B.dll
echo.
echo [M3I-B] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3i-b.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3I-B.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3I-B] SINGLE-VARIABLE TEST:
echo   motionVectorsDilated: FALSE -^> TRUE
 echo   Everything else stays on the M3I-A/M3H baseline.
echo.
echo [M3I-B] Recommended gameplay settings for comparison with the last good raw-flow run:
echo   - Geometry vectors OFF
 echo   - Validate motion vectors OFF
 echo   - LumeniteFX provider 3
 echo   - Neural Rendering OFF
 echo   - M3F mode 5 ^(75%% MV scale^)
 echo   - GTA capped to 60 FPS
 echo.
echo [M3I-B] After installing, do one steady horizontal pan and press ` once.
echo   A second capture with = is optional for repeatability.
echo.
echo [M3I-B] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
