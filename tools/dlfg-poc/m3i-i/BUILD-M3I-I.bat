@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3IH=..\m3i-h"
set "M2B=..\m2b"
set "CPP=%M2B%\feeder-src\src\dlss5-feed.cpp"
set "OUT=%~dp0m3i-i-build"

if not exist "%M3IH%\BUILD-M3I-H.bat" (
  echo [M3I-I] Missing %M3IH%\BUILD-M3I-H.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-I] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the complete M3I-H camera contract first:
rem GTA projection + live temporal transforms + live position/basis.
call "%M3IH%\BUILD-M3I-H.bat"
if errorlevel 1 exit /b %errorlevel%

rem Diagnostic: remove provider/object MV contribution and let DLSS-G derive camera motion
rem from depth + the GTA camera contract.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-I-CAMERA-ONLY-MOTION.ps1"
if errorlevel 1 exit /b %errorlevel%

powershell -NoProfile -Command ^
  "$t=Get-Content -LiteralPath '%CPP%' -Raw;" ^
  "$ok=$t.Contains('// M3I-I: camera-only motion diagnostic') -and $t.Contains('op->cameraMotionIncluded = false; // M3I-I: let DLSS-G synthesize camera motion from depth/camera') -and $t.Contains('op->motionVectorsInvalidValue = 1.17549435e-38f; // M3I-I: FLT_MIN sentinel, zero MV stays valid') -and $t.Contains('op->mvecScale[0] = 0.0f;') -and $t.Contains('op->mvecScale[1] = 0.0f;') -and $t.Contains('M3I-H: live GTA IV camera world position/basis') -and $t.Contains('M3I-G live GTA IV temporal camera transforms') -and $t.Contains('op->cameraViewToClip[2][2] = -a; // M3I-F: GTA IV right-handed projection') -and $t.Contains('op->motionVectorsDilated = false;');" ^
  "if(-not $ok){Write-Host '[M3I-I] SOURCE GUARD FAILED.'; exit 9}; Write-Host '[M3I-I] SOURCE GUARD PASSED: complete GTA camera contract + camera-only motion.'"
if errorlevel 1 exit /b %errorlevel%

call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3i-i.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3IH%\m3i-h-build\OptiScaler-M3I-H.dll" "%OUT%\OptiScaler-M3I-I.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3I-I] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3i-i.addon64
echo   %OUT%\OptiScaler-M3I-I.dll
echo.
echo [M3I-I] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3i-i.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3I-I.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3I-I] CAMERA-ONLY MOTION DIAGNOSTIC:
echo   - keeps M3I-H live camera position/right/up/forward
 echo   - keeps M3I-G live clipToPrevClip / prevClipToClip
 echo   - keeps M3I-F GTA right-handed projection
 echo   - keeps FOV=45deg near=0.05 far=1500 and real GTA depth
 echo   - NEW: cameraMotionIncluded=false
 echo   - NEW: provider MV contribution forced to zero via mvecScale=(0,0)
 echo   - NEW: motionVectorsInvalidValue=FLT_MIN so zero vectors remain valid
 echo.
echo [M3I-I] PURPOSE:
echo   Judge STATIC WORLD geometry during smooth camera motion.
echo   Moving cars/peds are expected to be wrong because object motion is intentionally removed.
echo   If static edges become dramatically sharper, estimated optical-flow MVs are the main blur source.
echo.
echo [M3I-I] Keep FusionFix FOV at 45, Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
