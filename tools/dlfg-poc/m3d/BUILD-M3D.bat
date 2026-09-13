@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3C=..\m3c"
set "M2B=..\m2b"
set "M3A=..\m3a-os"
set "OUT=%~dp0m3d-build"

if not exist "%M3C%\BUILD-M3C.bat" (
  echo [M3D] Missing %M3C%\BUILD-M3C.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3D] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)
if not exist "%M3A%\BUILD-M3A-OS.bat" (
  echo [M3D] Missing %M3A%\BUILD-M3A-OS.bat
  exit /b 1
)

rem First reproduce the exact M3C source trees. This also recreates the proven M3B-2B
rem producer, M3B-2A Vulkan consumer, and M3C 3-entry publication FIFO.
call "%M3C%\BUILD-M3C.bat"
if errorlevel 1 exit /b %errorlevel%

rem Layer only the default-off M3D present-origin gate on those generated source trees.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3D-PRESENT-GATE.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Rebuild Feeder from the already-patched generated source tree.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

rem Rebuild OptiScaler from its already-patched generated tree. Do NOT re-run the M3B-2A
rem apply script here: M3D deliberately patches the generated m3b2a-optiscaler.inc after M3C.
call "%M3A%\BUILD-M3A-OS.bat"
if errorlevel 1 exit /b %errorlevel%

if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%M2B%\m2b-build\dlss5-feed-m2b-eval.addon64" "%OUT%\dlss5-feed-m3d.addon64" >nul
if errorlevel 1 exit /b %errorlevel%
copy /Y "%M3A%\m3a-build\OptiScaler-M3A-OS.dll" "%OUT%\OptiScaler-M3D.dll" >nul
if errorlevel 1 exit /b %errorlevel%

echo.
echo [M3D] Build outputs only - NOTHING was copied into GTA IV:
echo   %OUT%\dlss5-feed-m3d.addon64
echo   %OUT%\OptiScaler-M3D.dll
echo.
echo [M3D] SHA-256:
certutil -hashfile "%OUT%\dlss5-feed-m3d.addon64" SHA256 | findstr /R /V "hash CertUtil"
certutil -hashfile "%OUT%\OptiScaler-M3D.dll" SHA256 | findstr /R /V "hash CertUtil"
echo.
echo [M3D] TEST MODE:
echo   dlfg_m3b2b_native=1
echo   dlfg_m3c_queue=1
echo   dlfg_m3d_injected_present_gate=1
echo   GtaivVulkanContinuousExternalPresent=true
echo.
echo [M3D] EXPECTED BEHAVIOR:
echo   - Feeder logs M3D accepted genuine real-present callbacks.
echo   - Synthetic/injected callbacks are suppressed before vk_frame/DLAA/DLSS-G work.
echo   - M3C sourceFrame delta=1 should now mean one generated frame per genuine game present.
echo   - Persistent 3-slot backpressure should disappear or be limited to startup/transients.
echo.
echo [M3D] HARDWARE-TEST LIMIT:
echo   Keep FusionFix Windowed = On and Windowed Borderless = On.
echo   Do NOT press Alt+Enter and do NOT switch Windowed Off.
endlocal
