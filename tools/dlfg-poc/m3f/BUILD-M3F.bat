@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3E=..\m3e"
set "M2B=..\m2b"
set "OUT=%~dp0m3f-build"

if not exist "%M3E%\BUILD-M3E.bat" (
  echo [M3F] Missing %M3E%\BUILD-M3E.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3F] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem Reproduce the complete M3E source/binary baseline first.
call "%M3E%\BUILD-M3E.bat"
if errorlevel 1 exit /b %errorlevel%

rem Patch only the DLSS-G interpretation of the existing motion-vector texture.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3F-MV-ALIGNMENT.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Rebuild Feeder only. M3E OptiScaler/pacing binary is reused unchanged.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3f.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3E%\m3e-build\OptiScaler-M3E.dll" "%OUT%\OptiScaler-M3F.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3F] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3f.addon64
echo   %OUT%\OptiScaler-M3F.dll
echo.
echo [M3F] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3f.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3F.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3F] MV PRESETS - selected later in dlss5-feed.cfg, no rebuild required:
echo   0 = baseline +X,+Y ^(current behavior^)
echo   1 = flip X
 echo   2 = flip Y
 echo   3 = flip X+Y
 echo   4 = 50%% magnitude
 echo   5 = 75%% magnitude
 echo   6 = 125%% magnitude
 echo   7 = 150%% magnitude
 echo.
echo [M3F] M3E presentation pacing remains available and unchanged.
echo [M3F] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
