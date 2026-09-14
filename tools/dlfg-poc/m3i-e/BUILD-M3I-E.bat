@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3ID=..\m3i-d"
set "M2B=..\m2b"
set "CPP=%M2B%\feeder-src\src\dlss5-feed.cpp"
set "OUT=%~dp0m3i-e-build"

if not exist "%M3ID%\BUILD-M3I-D.bat" (
  echo [M3I-E] Missing %M3ID%\BUILD-M3I-D.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-E] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Start from the clean guarded M3I-D build. That builder hard-resets the generated
rem Feeder checkout, reproduces M3H/M3I-A, then applies only the corrected static
rem GTA IV projection contract. This prevents old experimental patches leaking in.
call "%M3ID%\BUILD-M3I-D.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%CPP%" (
  echo [M3I-E] Missing generated source: %CPP%
  exit /b 1
)

rem Add diagnostic-only GTA IV camera matrix capture. No feature-11 values are changed.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-E-MATRIX-AUDIT.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Guard the generated source before compiling.
findstr /C:"M3I-E live GTA IV camera matrix audit" "%CPP%" >nul || (
  echo [M3I-E] ERROR: matrix-audit source marker missing.
  exit /b 1
)
findstr /C:"M3iViewportMemScanV3Tick" "%CPP%" >nul && (
  echo [M3I-E] ERROR: M3I-C scanner leaked into generated source.
  exit /b 1
)
findstr /C:"M3I-B full-res MV dilation diagnostic" "%CPP%" >nul && (
  echo [M3I-E] ERROR: M3I-B dilation patch leaked into generated source.
  exit /b 1
)
findstr /C:"op->motionVectorsDilated = false;" "%CPP%" >nul || (
  echo [M3I-E] ERROR: clean motionVectorsDilated=false baseline missing.
  exit /b 1
)
findstr /C:"near_z = 0.05f, far_z = 1500.0f, fov = 0.7853981634f" "%CPP%" >nul || (
  echo [M3I-E] ERROR: M3I-D corrected projection contract missing.
  exit /b 1
)

echo [M3I-E] SOURCE GUARD PASSED: clean M3I-D + matrix audit only.

rem Rebuild Feeder from the now-audited generated source. OptiScaler is unchanged.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3i-e.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3ID%\m3i-d-build\OptiScaler-M3I-D.dll" "%OUT%\OptiScaler-M3I-E.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3I-E] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3i-e.addon64
echo   %OUT%\OptiScaler-M3I-E.dll
echo.
echo [M3I-E] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3i-e.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3I-E.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3I-E] CAMERA MATRIX AUDIT:
echo   - corrected M3I-D FOV/near/far contract remains active
 echo   - motionVectorsDilated remains FALSE
 echo   - scans GTAIV.exe memory once for the main viewport
 echo   - samples WORLD/CAMERA/WVP/VIEWINV/VIEW/PROJ about twice per second
 echo   - logs matrix identity/composition errors and view movement delta
 echo   - does NOT feed GTA matrices to DLSS-G yet
 echo.
echo [M3I-E] TEST AFTER INSTALLING THE UPCOMING TEST BAT:
echo   Keep FusionFix FOV at 45. Stand still and smoothly pan the camera for 10-15 seconds,
echo   then walk/drive forward while turning for another 10-15 seconds and exit normally.
echo.
echo [M3I-E] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
