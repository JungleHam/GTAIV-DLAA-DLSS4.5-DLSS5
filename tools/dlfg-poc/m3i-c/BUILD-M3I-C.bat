@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3IA=..\m3i"
set "M2B=..\m2b"
set "OUT=%~dp0m3i-c-build"

if not exist "%M3IA%\BUILD-M3I-A.bat" (
  echo [M3I-C] Missing %M3IA%\BUILD-M3I-A.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-C] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the clean M3I-A/M3H baseline first.
call "%M3IA%\BUILD-M3I-A.bat"
if errorlevel 1 exit /b %errorlevel%

rem Add zero-behaviour-change remote read of GTA IV's live rage::grcViewport.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-C-VIEWPORT-AUDIT.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Only Feeder source changed. Rebuild from generated source tree.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3i-c.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3IA%\m3i-build\OptiScaler-M3I-A.dll" "%OUT%\OptiScaler-M3I-C.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3I-C] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3i-c.addon64
echo   %OUT%\OptiScaler-M3I-C.dll
echo.
echo [M3I-C] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3i-c.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3I-C.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3I-C] VIEWPORT AUDIT ONLY:
echo   - no DLSS-G values are changed yet
 echo   - finds GTAIV.exe from the 64-bit helper
 echo   - uses FusionFix's documented current-viewport signature
 echo   - reads live viewport FOV / aspect / near / far
 echo   - logs values whenever they change
 echo.
echo [M3I-C] TEST AFTER INSTALL:
echo   1. Start gameplay and stand still for a few seconds.
echo   2. Change FusionFix FOV to a noticeably different value.
echo   3. Return to gameplay for a few seconds, then exit.
echo   No A/G/B capture is required yet.
echo.
echo [M3I-C] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
