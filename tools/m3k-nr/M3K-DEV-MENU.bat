@echo off
setlocal EnableExtensions EnableDelayedExpansion
title GTA IV M3K Dev Menu

set "REPO=B:\Stuff\Mods\bbridgepatchtest FG 1\GTAIV-DLAA-DLSS5-m3k-nr"
set "GTA=B:\Games\Steam\steamapps\common\Grand Theft Auto IV\GTAIV"
set "TREX=%GTA%\.trex"
set "CFG=%TREX%\m3k-nr.ini"
set "LOG=%TREX%\dlss5-feed.log"
set "OUT=%REPO%\tools\m3k-nr\out-m3k"
set "BACKROOT=%GTA%\nonvanillastuff\M3K-backups"
set "A2BRANCH=gtaiv-m3k-a2-sr-profiles"

:menu
cls
echo ============================================================
echo                  GTA IV - M3K DEV MENU
echo ============================================================
echo Repo: %REPO%
echo GTA : %GTA%
echo.
set "CURMODE=missing"
if exist "%CFG%" for /f "tokens=1,* delims==" %%A in ('findstr /R /C:"^Mode=" "%CFG%" 2^>nul') do set "CURMODE=%%B"
echo Current M3K Mode: !CURMODE!
echo.
echo [1] Show Git / install status
echo [2] Mode 0 - DLAA only
echo [3] Mode 1 - NR create only
echo [4] Mode 2 - NR then DLAA
echo [5] Open m3k-nr.ini in Notepad
echo [6] Show recent M3K log lines
echo [7] Build current clean repo branch
echo [8] Install latest build to GTA (with backup)
echo [9] Switch clean worktree to A2 SR branch
echo [R] Restore newest backed-up Feeder
echo [Q] Quit
echo.
echo NOTE: Modes 3+ / SR profiles are not exposed until the A2 build
echo       actually implements them.
echo.
choice /C 123456789RQ /N /M "Choose: "
set "C=%ERRORLEVEL%"
if "%C%"=="1" goto status
if "%C%"=="2" goto mode0
if "%C%"=="3" goto mode1
if "%C%"=="4" goto mode2
if "%C%"=="5" goto opencfg
if "%C%"=="6" goto log
if "%C%"=="7" goto build
if "%C%"=="8" goto install
if "%C%"=="9" goto a2branch
if "%C%"=="10" goto restore
if "%C%"=="11" goto end
goto menu

:status
cls
echo === REPO STATUS ===
pushd "%REPO%" || goto repoerr
git branch --show-current
git log -1 --oneline
git status --short
popd
echo.
echo === INSTALLED FILES ===
for %%F in ("%TREX%\dlss5-feed.addon64" "%TREX%\m3k-nr.ini" "%TREX%\m3k\m3k-nvngx.dll" "%TREX%\m3k\nvngx_dlssnr.dll") do if exist "%%~F" (echo [OK] %%~F) else (echo [MISSING] %%~F)
echo.
pause
goto menu

:mode0
call :setmode 0
goto menu
:mode1
call :setmode 1
goto menu
:mode2
call :setmode 2
goto menu

:setmode
set "NEWMODE=%~1"
if not exist "%CFG%" (
  echo ERROR: %CFG% not found.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p='%CFG%'; $t=Get-Content -LiteralPath $p; if($t -match '^Mode\s*='){ $t=$t -replace '^Mode\s*=\s*\d+\s*$','Mode=%NEWMODE%' } else { $t += 'Mode=%NEWMODE%' }; Set-Content -LiteralPath $p -Value $t -Encoding ASCII"
echo.
echo M3K Mode set to %NEWMODE%.
echo Allow about 1-2 seconds for the hot poll while GTA is running.
timeout /t 2 /nobreak >nul
exit /b 0

:opencfg
if exist "%CFG%" (start "" notepad.exe "%CFG%") else (echo ERROR: %CFG% not found. & pause)
goto menu

:log
cls
if not exist "%LOG%" (
  echo No log found: %LOG%
) else (
  echo === LAST M3K / FEATURE-18 / DLSS LINES ===
  powershell.exe -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Tail 1200 | Select-String -Pattern 'M3K','feature 18','DLAA running','DLSS SR','FAILED','exception' | Select-Object -Last 100 | ForEach-Object { $_.Line }"
)
echo.
pause
goto menu

:build
cls
echo === BUILDING CURRENT BRANCH ===
echo Commands run in:
echo %REPO%
echo.
pushd "%REPO%" || goto repoerr
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\m3k-nr\build.ps1"
set "RC=%ERRORLEVEL%"
popd
echo.
if not "%RC%"=="0" (echo BUILD FAILED with exit code %RC%.) else (echo BUILD COMPLETE. & echo Output: %OUT%)
pause
goto menu

:install
cls
echo === INSTALL LATEST BUILD ===
echo GTA and NvRemixBridge.exe must be CLOSED.
echo.
tasklist /FI "IMAGENAME eq GTAIV.exe" 2>nul | find /I "GTAIV.exe" >nul && (echo ERROR: GTAIV.exe is running. & pause & goto menu)
tasklist /FI "IMAGENAME eq NvRemixBridge.exe" 2>nul | find /I "NvRemixBridge.exe" >nul && (echo ERROR: NvRemixBridge.exe is running. & pause & goto menu)
if not exist "%OUT%\dlss5-feed.addon64" (echo ERROR: No build. Run option 7 first. & pause & goto menu)
if not exist "%OUT%\m3k\m3k-nvngx.dll" (echo ERROR: m3k-nvngx.dll missing. & pause & goto menu)
for /f %%T in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%T"
set "BACK=%BACKROOT%\!STAMP!"
mkdir "!BACK!" >nul 2>&1
if exist "%TREX%\dlss5-feed.addon64" copy /Y "%TREX%\dlss5-feed.addon64" "!BACK!\dlss5-feed.addon64" >nul
if exist "%TREX%\m3k-nr.ini" copy /Y "%TREX%\m3k-nr.ini" "!BACK!\m3k-nr.ini" >nul
if exist "%TREX%\m3k\m3k-nvngx.dll" (mkdir "!BACK!\m3k" >nul 2>&1 & copy /Y "%TREX%\m3k\m3k-nvngx.dll" "!BACK!\m3k\m3k-nvngx.dll" >nul)
copy /Y "%OUT%\dlss5-feed.addon64" "%TREX%\dlss5-feed.addon64" >nul
if not exist "%TREX%\m3k" mkdir "%TREX%\m3k" >nul 2>&1
copy /Y "%OUT%\m3k\m3k-nvngx.dll" "%TREX%\m3k\m3k-nvngx.dll" >nul
if not exist "%CFG%" copy /Y "%OUT%\m3k-nr.ini" "%CFG%" >nul
echo Installed. Backup: !BACK!
echo Existing nvngx_dlssnr.dll and live m3k-nr.ini were preserved.
echo.
pause
goto menu

:a2branch
cls
echo === SWITCH CLEAN WORKTREE TO %A2BRANCH% ===
echo Commands run in:
echo %REPO%
echo.
pushd "%REPO%" || goto repoerr
for /f "delims=" %%S in ('git status --porcelain') do set "DIRTY=1"
if defined DIRTY (
  echo ERROR: Worktree has local changes. Nothing was switched.
  git status --short
  popd
  pause
  goto menu
)
git fetch origin
git switch "%A2BRANCH%" 2>nul
if errorlevel 1 git switch -c "%A2BRANCH%" --track "origin/%A2BRANCH%"
git branch --show-current
git log -1 --oneline
popd
echo.
pause
goto menu

:restore
cls
echo === RESTORE NEWEST FEEDER BACKUP ===
set "LATEST="
if not exist "%BACKROOT%" (echo No backup folder exists. & pause & goto menu)
for /f "delims=" %%D in ('dir /B /AD /O-D "%BACKROOT%" 2^>nul') do if not defined LATEST set "LATEST=%%D"
if not defined LATEST (echo No backups found. & pause & goto menu)
set "BACK=%BACKROOT%\!LATEST!"
if not exist "!BACK!\dlss5-feed.addon64" (echo Newest backup has no Feeder: !BACK! & pause & goto menu)
copy /Y "!BACK!\dlss5-feed.addon64" "%TREX%\dlss5-feed.addon64" >nul
echo Restored Feeder from !BACK!
echo.
pause
goto menu

:repoerr
echo ERROR: Could not enter repo: %REPO%
pause
goto menu

:end
endlocal
exit /b 0
