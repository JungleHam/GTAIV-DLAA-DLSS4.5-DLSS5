@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "M3IA=..\m3i"
set "M2B=..\m2b"
set "FEEDER=%M2B%\feeder-src"
set "OUT=%~dp0m3i-d-build"

if not exist "%M3IA%\BUILD-M3I-A.bat" (
  echo [M3I-D] Missing %M3IA%\BUILD-M3I-A.bat
  exit /b 1
)
if not exist "%M2B%\BUILD-M2B-PROBE.bat" (
  echo [M3I-D] Missing %M2B%\BUILD-M2B-PROBE.bat
  exit /b 1
)

rem IMPORTANT: the generated feeder-src checkout survives normal branch switches.
rem M3I-C/M3I-B patches can therefore leak into later experiments unless we explicitly
rem restore the generated checkout to its upstream HEAD before rebuilding the milestone chain.
if not exist "%FEEDER%\.git" (
  echo [M3I-D] ERROR: %FEEDER% is not a Git checkout.
  echo [M3I-D] Refusing to claim a clean one-variable test because stale generated patches cannot be removed safely.
  exit /b 1
)

echo [M3I-D] Resetting generated Feeder checkout to a clean upstream HEAD...
git -C "%FEEDER%" reset --hard HEAD
if errorlevel 1 exit /b %errorlevel%
git -C "%FEEDER%" clean -fd
if errorlevel 1 exit /b %errorlevel%

rem Reproduce the clean M3I-A / M3H baseline from that reset source tree.
call "%M3IA%\BUILD-M3I-A.bat"
if errorlevel 1 exit /b %errorlevel%

rem Guard against exactly the contamination caught by the first M3I-D hardware run.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%FEEDER%\src\dlss5-feed.cpp'; $t=Get-Content -LiteralPath $p -Raw;" ^
  "if($t.Contains('M3I-C v3 direct viewport-structure memory scan')){throw 'STALE M3I-C v3 scanner survived clean rebuild'};" ^
  "if($t.Contains('M3I-B full-res MV dilation diagnostic')){throw 'STALE M3I-B motionVectorsDilated=true survived clean rebuild'};" ^
  "if(-not $t.Contains('op->motionVectorsDilated = false;')){throw 'Expected clean baseline motionVectorsDilated=false is missing'};" ^
  "Write-Host '[M3I-D] Clean baseline guard PASSED: no M3I-B, no M3I-C, motionVectorsDilated=false.'"
if errorlevel 1 exit /b %errorlevel%

rem One-variable causal test: replace only the fake projection/depth contract.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-M3I-D-PROJECTION.ps1"
if errorlevel 1 exit /b %errorlevel%

rem Only Feeder source changed. Rebuild from the generated source tree.
call "%M2B%\BUILD-M2B-PROBE.bat"
if errorlevel 1 exit /b %errorlevel%

rem Final contamination guard on the exact source that produced the binary.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%FEEDER%\src\dlss5-feed.cpp'; $t=Get-Content -LiteralPath $p -Raw;" ^
  "if($t.Contains('M3I-C v3 direct viewport-structure memory scan')){throw 'M3I-C contamination present in final source'};" ^
  "if($t.Contains('M3I-B full-res MV dilation diagnostic')){throw 'M3I-B contamination present in final source'};" ^
  "if(-not $t.Contains('M3I-D: GTA IV main viewport contract, 45 degrees')){throw 'M3I-D projection patch missing from final source'};" ^
  "if(-not $t.Contains('op->motionVectorsDilated = false;')){throw 'Final source is not the intended motionVectorsDilated=false baseline'};" ^
  "Write-Host '[M3I-D] FINAL SOURCE GUARD PASSED.'"
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
echo [M3I-D] PROJECTION CONTRACT TEST v2 CLEAN BUILD:
echo   FOV    60 deg  ^> 45 deg
echo   near   0.10    ^> 0.05
echo   far    1000    ^> 1500
echo   aspect remains framebuffer aspect ^(2560/1440 = 1.777777...^)
echo   motionVectorsDilated remains FALSE ^(clean M3H/M3I-A baseline^)
echo.
echo [M3I-D] IMPORTANT:
echo   - generated Feeder checkout was hard-reset before rebuilding the milestone chain
 echo   - M3I-C viewport memory scanning is NOT included
 echo   - M3I-B motionVectorsDilated diagnostic is NOT included
 echo   - no other DLSS-G constants are intentionally changed
 echo   - keep FusionFix FOV at 45 for this A/B
 echo.
echo [M3I-D] Keep FusionFix Windowed ON + Borderless ON. Do not Alt+Enter.
endlocal
