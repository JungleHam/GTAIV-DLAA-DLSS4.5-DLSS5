@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "BB_SELF=%~f0"
set "PATCHED=%~dp0ReShade64-bbridge.dll"
set "RESHADESYS=C:\ProgramData\ReShade\ReShade64.dll"
set "BACKUP=C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input"

rem Make this usable by double-clicking: request UAC automatically, then continue.
net session >nul 2>nul
if errorlevel 1 (
  echo.
  echo Administrator permission is required to install the patched ReShade Vulkan DLL.
  echo Windows will now show a User Account Control prompt. Click Yes to continue.
  echo.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:BB_SELF -Verb RunAs" || (
    echo ERROR: Could not request Administrator permission.
    pause
    exit /b 1
  )
  exit /b 0
)

set "GAME=%~1"
if not defined GAME (
  echo ============================================================
  echo ReShade b-bridge input patch installer
  echo ============================================================
  echo.
  echo Please enter the GTA IV game folder that contains GTAIV.exe.
  echo You can COPY/PASTE the path, or DRAG THE GTAIV FOLDER into this window.
  echo.
  echo Example:
  echo   B:\Games\Steam\steamapps\common\Grand Theft Auto IV\GTAIV
  echo.
  set /p "GAME=Game folder: "
)

if not defined GAME (
  echo.
  echo ERROR: No game folder was entered.
  pause
  exit /b 1
)

rem Drag-and-drop usually adds quotes; remove them.
set "GAME=%GAME:"=%"

rem Be forgiving if the user pasted GTAIV.exe itself instead of its folder.
for %%I in ("%GAME%") do if /I "%%~nxI"=="GTAIV.exe" set "GAME=%%~dpI"

rem Be forgiving if the user selected the outer "Grand Theft Auto IV" folder.
if not exist "%GAME%\GTAIV.exe" if exist "%GAME%\GTAIV\GTAIV.exe" set "GAME=%GAME%\GTAIV"

set "TREX=%GAME%\.trex"
set "BB_TREX=%TREX%"
set "POC=%TREX%\bridge-input.addon64"
set "POCDISABLED=%TREX%\bridge-input.addon64.poc-disabled"

echo.
echo Using game folder:
echo   %GAME%
echo.

if not exist "%GAME%\GTAIV.exe" (
  echo ERROR: GTAIV.exe was not found there.
  echo.
  echo Make sure you entered the folder that actually contains GTAIV.exe.
  echo On the Steam Complete Edition it normally ends in:
  echo   \Grand Theft Auto IV\GTAIV
  pause
  exit /b 1
)
if not exist "%TREX%\NvRemixBridge.exe" (
  echo ERROR: b-bridge server not found:
  echo   %TREX%\NvRemixBridge.exe
  echo.
  echo Complete Steps 1 and 2 of the main README first.
  pause
  exit /b 1
)
if not exist "%PATCHED%" (
  echo ERROR: ReShade64-bbridge.dll not found.
  echo.
  echo Double-click BUILD.bat first and wait for it to report SUCCESS.
  pause
  exit /b 1
)
if not exist "%RESHADESYS%" (
  echo ERROR: Existing global ReShade Vulkan DLL not found:
  echo   %RESHADESYS%
  echo.
  echo Install the ReShade Vulkan layer through Install-DLAA.bat first.
  pause
  exit /b 1
)

for %%P in (GTAIV.exe NvRemixBridge.exe) do (
  tasklist /FI "IMAGENAME eq %%P" 2>nul | find /I "%%P" >nul && (
    echo ERROR: %%P is running. Fully close GTA IV first.
    pause
    exit /b 1
  )
)

if not exist "%BACKUP%" (
  echo Backing up current ReShade64.dll...
  copy /y "%RESHADESYS%" "%BACKUP%" >nul || (
    echo ERROR: Could not create backup.
    pause
    exit /b 1
  )
) else (
  echo Existing backup preserved:
  echo   %BACKUP%
)

if exist "%POC%" (
  echo Disabling old bridge-input POC add-on...
  if exist "%POCDISABLED%" del /q "%POCDISABLED%"
  ren "%POC%" "bridge-input.addon64.poc-disabled" || (
    echo ERROR: Could not disable old POC add-on.
    pause
    exit /b 1
  )
)

echo Installing patched global ReShade Vulkan DLL...
copy /y "%PATCHED%" "%RESHADESYS%" >nul || (
  echo ERROR: Could not replace %RESHADESYS%
  echo Another Vulkan/ReShade application may still have it loaded.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p=Join-Path $env:BB_TREX 'bridge.conf'; if(!(Test-Path -LiteralPath $p)){throw 'bridge.conf not found'}; $t=[IO.File]::ReadAllText($p); foreach($kv in @(@('client.DirectInput.forward.mousePolicy','3'),@('client.DirectInput.forward.keyboardPolicy','3'))){$k=$kv[0];$v=$kv[1];$pat='(?m)^\s*'+[regex]::Escape($k)+'\s*=.*$';$line=$k+' = '+$v;if($t -match $pat){$t=[regex]::Replace($t,$pat,$line)}else{if($t.Length -gt 0 -and !$t.EndsWith([Environment]::NewLine)){$t+=[Environment]::NewLine};$t+=$line+[Environment]::NewLine}};[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))" || (
  echo WARNING: Could not update bridge.conf automatically.
  echo Add these manually:
  echo   client.DirectInput.forward.mousePolicy = 3
  echo   client.DirectInput.forward.keyboardPolicy = 3
)

echo.
echo ============================================================
echo INSTALLED SUCCESSFULLY
echo ============================================================
echo.
echo Launch GTA IV normally and press HOME to test the ReShade interface.
echo.
echo To undo this patch later, simply double-click RESTORE_ORIGINAL.bat.
echo It will ask for the same GTA IV folder and request Administrator permission itself.
echo.
pause
