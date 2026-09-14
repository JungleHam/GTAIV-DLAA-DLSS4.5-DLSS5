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

rem V1: documented FusionFix current-viewport signature audit.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-C-VIEWPORT-AUDIT.ps1"
if errorlevel 1 exit /b %errorlevel%

rem V2: relaxed x86 absolute-MOV locator plus stage-by-stage diagnostics.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-C-V2-DIAGNOSTIC.ps1"
if errorlevel 1 exit /b %errorlevel%

rem V3: V2 proved GTAIV.exe/module reads are healthy but no referenced candidate
rem validated. Search committed GTA IV memory directly for FusionFix's documented
rem grcViewport field layout, then monitor candidate values for the FOV change.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-C-V3-MEMSCAN.ps1"
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
echo [M3I-C] VIEWPORT AUDIT V3 ONLY:
echo   - no DLSS-G values are changed yet
 echo   - V1/V2 signature locators are kept for provenance but are not called at runtime
 echo   - scans GTA IV committed memory for the documented grcViewport layout itself
 echo   - first two passes scan writable memory; third pass broadens to all readable memory
 echo   - logs every plausible 2560x1440 viewport candidate and any FOV/near/far changes
 echo.
echo [M3I-C] TEST AFTER INSTALL:
echo   1. Start gameplay and stand still for a few seconds.
echo   2. Change FusionFix FOV to a noticeably different value.
echo   3. Return to gameplay for 10 seconds, then exit.
echo   No A/G/B capture is required yet.
echo.
echo [M3I-C] A short hitch during the memory scan is possible; this is diagnostic only.
echo [M3I-C] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
