@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "PATCHED=%~dp0ReShade64-bbridge.dll"
set "RESHADESYS=C:\ProgramData\ReShade\ReShade64.dll"
set "BACKUP=C:\ProgramData\ReShade\ReShade64.dll.pre-bbridge-input"

if "%~1"=="" (
  echo Usage:
  echo   INSTALL.bat "X:\path\to\Grand Theft Auto IV\GTAIV"
  echo.
  echo Example:
  echo   INSTALL.bat "B:\Games\Steam\steamapps\common\Grand Theft Auto IV\GTAIV"
  pause
  exit /b 1
)

set "GAME=%~1"
set "TREX=%GAME%\.trex"
set "POC=%TREX%\bridge-input.addon64"
set "POCDISABLED=%TREX%\bridge-input.addon64.poc-disabled"

net session >nul 2>nul
if errorlevel 1 (
  echo ERROR: Right-click Command Prompt/Terminal and run as Administrator,
  echo then run this script from there.
  pause
  exit /b 1
)

if not exist "%GAME%\GTAIV.exe" (
  echo ERROR: GTAIV.exe not found in:
  echo   %GAME%
  pause
  exit /b 1
)
if not exist "%TREX%\NvRemixBridge.exe" (
  echo ERROR: b-bridge server not found:
  echo   %TREX%\NvRemixBridge.exe
  pause
  exit /b 1
)
if not exist "%PATCHED%" (
  echo ERROR: ReShade64-bbridge.dll not found. Run BUILD.bat first.
  pause
  exit /b 1
)
if not exist "%RESHADESYS%" (
  echo ERROR: Existing global ReShade Vulkan DLL not found:
  echo   %RESHADESYS%
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
  "$p='%TREX%\bridge.conf'; if(!(Test-Path -LiteralPath $p)){throw 'bridge.conf not found'}; $t=[IO.File]::ReadAllText($p); foreach($kv in @(@('client.DirectInput.forward.mousePolicy','3'),@('client.DirectInput.forward.keyboardPolicy','3'))){$k=$kv[0];$v=$kv[1];$pat='(?m)^\s*'+[regex]::Escape($k)+'\s*=.*$';$line=$k+' = '+$v;if($t -match $pat){$t=[regex]::Replace($t,$pat,$line)}else{if($t.Length -gt 0 -and !$t.EndsWith([Environment]::NewLine)){$t+=[Environment]::NewLine};$t+=$line+[Environment]::NewLine}};[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))" || (
  echo WARNING: Could not update bridge.conf automatically.
  echo Add these manually:
  echo   client.DirectInput.forward.mousePolicy = 3
  echo   client.DirectInput.forward.keyboardPolicy = 3
)

echo.
echo INSTALLED.
echo Launch GTA IV, press HOME and test the ReShade / DFC interface.
echo.
echo Rollback:
echo   RESTORE_ORIGINAL.bat "%GAME%"
pause
