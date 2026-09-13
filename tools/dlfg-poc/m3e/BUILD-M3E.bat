@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3D=..\m3d"
set "M2B=..\m2b"
set "M3A=..\m3a-os"
set "OUT=%~dp0m3e-build"

if not exist "%M3D%\BUILD-M3D.bat" (
  echo [M3E] Missing %M3D%\BUILD-M3D.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3E] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)
if not exist "%M3A%\BUILD-M3A-OS.bat" (
  echo [M3E] Missing %M3A%\BUILD-M3A-OS.bat
  exit /b 1
)

rem Reproduce the exact proven M3D source trees first.
call "%M3D%\BUILD-M3D.bat"
if errorlevel 1 exit /b %errorlevel%

rem Layer only the default-off display-pacing experiment on the generated OptiScaler tree.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3E-PACING.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Feeder code is deliberately unchanged from M3D. Rebuild only OptiScaler after pacing patch.
call "%M3A%\BUILD-M3A-OS.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M3D%\m3d-build\dlss5-feed-m3d.addon64" "%OUT%\dlss5-feed-m3e.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3A%\m3a-build\OptiScaler-M3A-OS.dll" "%OUT%\OptiScaler-M3E.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3E] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3e.addon64
echo   %OUT%\OptiScaler-M3E.dll
echo.
echo [M3E] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3e.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3E.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3E] TEST MODE:
echo   dlfg_m3b2b_native=1
echo   dlfg_m3c_queue=1
echo   dlfg_m3d_injected_present_gate=1
echo   GtaivVulkanContinuousExternalPresent=true
echo   GtaivVulkanHalfIntervalPacing=true
echo.
echo [M3E] EXPECTED BEHAVIOR:
echo   - First ~120 genuine real presents run like M3D while the unpaced interval is learned.
echo   - Then M3E logs a locked baseline and midpoint target.
echo   - Generated present remains first; original real present is submitted near half an unpaced frame later.
echo   - M3E timing logs show submitGap close to target.
echo   - M3D/M3C/M3B-2B safety and milestones remain intact.
echo.
echo [M3E] HARDWARE-TEST LIMIT:
echo   Keep FusionFix Windowed = On and Windowed Borderless = On.
echo   Do NOT press Alt+Enter and do NOT switch Windowed Off.
endlocal
