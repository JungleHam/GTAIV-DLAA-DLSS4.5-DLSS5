@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3H=..\m3h"
set "M2B=..\m2b"
set "OUT=%~dp0m3i-build"

if not exist "%M3H%\BUILD-M3H.bat" (
  echo [M3I-A] Missing %M3H%\BUILD-M3H.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-A] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the complete hardware-proven M3H baseline first.
call "%M3H%\BUILD-M3H.bat"
if errorlevel 1 exit /b %errorlevel%

rem Add zero-behaviour-change logging for DLSS-G create/eval dimensions, actual resources,
rem subrects and feeder work-resolution settings.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-A-RESOLUTION-AUDIT.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Only Feeder source changed. Rebuild from the patched generated source tree.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3i-a.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3H%\m3h-build\OptiScaler-M3H.dll" "%OUT%\OptiScaler-M3I-A.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3I-A] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3i-a.addon64
echo   %OUT%\OptiScaler-M3I-A.dll
echo.
echo [M3I-A] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3i-a.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3I-A.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3I-A] RESOLUTION / SUBRECT AUDIT ONLY:
echo   - no DLSS-G values are intentionally changed
echo   - logs feature-11 create Width/Height/RenderWidth/RenderHeight
 echo   - logs actual D3D12 resource descriptors for Color/Backbuffer/Depth/MV/Generated
 echo   - logs every feature-11 eval subrect base + size
 echo   - logs feeder work_resolution/work_upscale/work_sharpness
 echo.
echo [M3I-A] After installing the test build, one short gameplay run is enough.
echo   No manual capture hotkey is required for the first audit.
echo.
echo [M3I-A] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
