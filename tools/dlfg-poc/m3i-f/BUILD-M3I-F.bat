@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3ID=..\m3i-d"
set "M2B=..\m2b"
set "CPP=%M2B%\feeder-src\src\dlss5-feed.cpp"
set "OUT=%~dp0m3i-f-build"

if not exist "%M3ID%\BUILD-M3I-D.bat" (
  echo [M3I-F] Missing %M3ID%\BUILD-M3I-D.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-F] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the clean M3I-D baseline. Its builder hard-resets the generated
rem Feeder checkout first and guards against M3I-B/M3I-C contamination.
call "%M3ID%\BUILD-M3I-D.bat"
if errorlevel 1 exit /b %errorlevel%

rem One-variable causal test: keep 45deg / 0.05 / 1500, but correct the
rem cameraViewToClip handedness/signs to match GTA IV's audited PROJ matrix.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-F-PROJECTION-HANDEDNESS.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Refuse to build if the exact intended source contract is not present.
powershell -NoProfile -Command ^
  "$t=Get-Content -LiteralPath '%CPP%' -Raw;" ^
  "$ok=$t.Contains('op->cameraViewToClip[2][2] = -a; // M3I-F: GTA IV right-handed projection') -and $t.Contains('op->cameraViewToClip[2][3] = -1.0f; // M3I-F: GTA IV right-handed projection') -and $t.Contains('op->clipToCameraView[3][2] = -1.0f; // M3I-F: exact inverse of GTA IV projection') -and $t.Contains('const float near_z = 0.05f, far_z = 1500.0f, fov = 0.7853981634f;') -and $t.Contains('op->motionVectorsDilated = false;') -and -not $t.Contains('M3I-C v3 direct viewport-structure memory scan') -and -not $t.Contains('M3I-B full-res MV dilation diagnostic');" ^
  "if(-not $ok){Write-Host '[M3I-F] SOURCE GUARD FAILED.'; exit 9}; Write-Host '[M3I-F] SOURCE GUARD PASSED: clean M3I-D + GTA RH projection only.'"
if errorlevel 1 exit /b %errorlevel%

call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3i-f.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3ID%\m3i-d-build\OptiScaler-M3I-D.dll" "%OUT%\OptiScaler-M3I-F.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3I-F] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3i-f.addon64
echo   %OUT%\OptiScaler-M3I-F.dll
echo.
echo [M3I-F] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3i-f.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3I-F.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3I-F] PROJECTION MATRIX CONVENTION TEST:
echo   M3I-D scalars remain: FOV=45deg near=0.05 far=1500 aspect=16:9
echo   OLD DLSS-G projection: m22=+a, m23=+1 ^(left-handed^)
echo   GTA IV audited projection: m22=-a, m23=-1 ^(right-handed^)
echo   clipToCameraView inverse m32 also changes +1 to -1
echo.
echo [M3I-F] IMPORTANT:
echo   - motionVectorsDilated remains FALSE
 echo   - temporal clip transforms remain identity for this one-variable test
 echo   - cameraMotionIncluded remains unchanged
 echo   - M3I-C / M3I-E memory scanners are NOT included
 echo   - keep FusionFix FOV at 45
 echo.
echo [M3I-F] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
