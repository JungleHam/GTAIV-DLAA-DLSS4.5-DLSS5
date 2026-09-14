@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3IG=..\m3i-g"
set "M2B=..\m2b"
set "CPP=%M2B%\feeder-src\src\dlss5-feed.cpp"
set "OUT=%~dp0m3i-h-build"

if not exist "%M3IG%\BUILD-M3I-G.bat" (
  echo [M3I-H] Missing %M3IG%\BUILD-M3I-G.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-H] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the clean M3I-G baseline first.
call "%M3IG%\BUILD-M3I-G.bat"
if errorlevel 1 exit /b %errorlevel%

rem One conceptual variable: replace zero/fixed camera world metadata with GTA's
rem live position/right/up/forward extracted from the already-read VIEWINV matrix.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-H-CAMERA-BASIS.ps1"
if errorlevel 1 exit /b %errorlevel%

powershell -NoProfile -Command ^
  "$t=Get-Content -LiteralPath '%CPP%' -Raw;" ^
  "$ok=$t.Contains('// M3I-H: live GTA IV camera world position/basis') -and $t.Contains('op->cameraPos[0] = cur.viewInv[12];') -and $t.Contains('op->cameraFwd[0] = -cur.viewInv[8];') -and $t.Contains('M3gApplyTemporalCamera(op, reset); // M3I-G: live GTA IV current/previous camera transform') -and $t.Contains('op->motionVectorsDilated = false;');" ^
  "if(-not $ok){Write-Host '[M3I-H] SOURCE GUARD FAILED.'; exit 9}; Write-Host '[M3I-H] SOURCE GUARD PASSED: M3I-G + live GTA camera basis.'"
if errorlevel 1 exit /b %errorlevel%

call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3i-h.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3IG%\m3i-g-build\OptiScaler-M3I-G.dll" "%OUT%\OptiScaler-M3I-H.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3I-H] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3i-h.addon64
echo   %OUT%\OptiScaler-M3I-H.dll
echo.
echo [M3I-H] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3i-h.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3I-H.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3I-H] LIVE CAMERA BASIS TEST:
echo   - keeps M3I-G live clipToPrevClip / prevClipToClip
 echo   - keeps M3I-F GTA right-handed projection
 echo   - keeps FOV=45deg near=0.05 far=1500
 echo   - keeps MV mode/scale/data unchanged
 echo   - cameraMotionIncluded remains TRUE
 echo   - NEW: cameraPos/right/up/forward come from GTA VIEWINV every evaluation
 echo.
echo [M3I-H] Keep FusionFix FOV at 45, Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
