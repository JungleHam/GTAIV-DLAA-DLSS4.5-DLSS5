@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3IA=..\m3i"
set "M2B=..\m2b"
set "OUT=%~dp0m3i-d-build"

if not exist "%M3IA%\BUILD-M3I-A.bat" (
  echo [M3I-D] Missing %M3IA%\BUILD-M3I-A.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-D] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the clean M3I-A / M3H baseline first. This intentionally does NOT
rem include the M3I-C viewport memory scanner.
call "%M3IA%\BUILD-M3I-A.bat"
if errorlevel 1 exit /b %errorlevel%

rem One-variable causal test: replace only the fake projection/depth contract.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-D-PROJECTION.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Only Feeder source changed. Rebuild from the generated source tree.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3i-d.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3IA%\m3i-build\OptiScaler-M3I-A.dll" "%OUT%\OptiScaler-M3I-D.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3I-D] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3i-d.addon64
echo   %OUT%\OptiScaler-M3I-D.dll
echo.
echo [M3I-D] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3i-d.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3I-D.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3I-D] PROJECTION CONTRACT TEST:
echo   FOV    60 deg  ^> 45 deg
echo   near   0.10    ^> 0.05
echo   far    1000    ^> 1500
echo   aspect remains framebuffer aspect ^(2560/1440 = 1.777777...^)
echo.
echo [M3I-D] IMPORTANT:
echo   - based on the clean M3I-A/M3H baseline
 echo   - M3I-C viewport memory scanning is NOT included
 echo   - no other DLSS-G constants are intentionally changed
 echo   - keep FusionFix FOV at 45 for this A/B
 echo.
echo [M3I-D] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
