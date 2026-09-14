@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3IF=..\m3i-f"
set "M2B=..\m2b"
set "CPP=%M2B%\feeder-src\src\dlss5-feed.cpp"
set "OUT=%~dp0m3i-g-build"

if not exist "%M3IF%\BUILD-M3I-F.bat" (
  echo [M3I-G] Missing %M3IF%\BUILD-M3I-F.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-G] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the clean M3I-F baseline first: corrected 45deg/0.05/1500
rem right-handed projection, no M3I-C/M3I-E scanner and motionVectorsDilated=false.
call "%M3IF%\BUILD-M3I-F.bat"
if errorlevel 1 exit /b %errorlevel%

rem One new variable: fill feature-11 temporal clip transforms from GTA IV's
rem live current/previous VIEW matrices. The viewport is found once, then only
rem a tiny read of VIEW/VIEWINV happens per evaluation.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-G-TEMPORAL-CAMERA.ps1"
if errorlevel 1 exit /b %errorlevel%

powershell -NoProfile -Command ^
  "$t=Get-Content -LiteralPath '%CPP%' -Raw;" ^
  "$ok=$t.Contains('M3gApplyTemporalCamera(op, reset); // M3I-G: live GTA IV current/previous camera transform') -and $t.Contains('M3I-G live GTA IV temporal camera transforms') -and $t.Contains('op->cameraViewToClip[2][2] = -a; // M3I-F: GTA IV right-handed projection') -and $t.Contains('op->motionVectorsDilated = false;') -and -not $t.Contains('M3I-C v3 direct viewport-structure memory scan') -and -not $t.Contains('M3I-E live GTA IV camera matrix audit');" ^
  "if(-not $ok){Write-Host '[M3I-G] SOURCE GUARD FAILED.'; exit 9}; Write-Host '[M3I-G] SOURCE GUARD PASSED: clean M3I-F + live temporal camera transforms.'"
if errorlevel 1 exit /b %errorlevel%

call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3i-g.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3IF%\m3i-f-build\OptiScaler-M3I-F.dll" "%OUT%\OptiScaler-M3I-G.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3I-G] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3i-g.addon64
echo   %OUT%\OptiScaler-M3I-G.dll
echo.
echo [M3I-G] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3i-g.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3I-G.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3I-G] LIVE TEMPORAL CAMERA TEST:
echo   - keeps M3I-F GTA right-handed projection
 echo   - keeps FOV=45deg near=0.05 far=1500
 echo   - keeps MV mode/scale/data unchanged
 echo   - keeps cameraMotionIncluded=true
 echo   - changes clipToPrevClip / prevClipToClip from identity to GTA live camera transforms
 echo   - one-time viewport scan at startup; no M3I-E audit logger
 echo.
echo [M3I-G] Keep FusionFix FOV at 45, Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
