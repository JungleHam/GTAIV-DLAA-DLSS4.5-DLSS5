@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "GTA=%~dp0"
for %%I in ("%GTA%..") do set "PARENT=%%~fI"

if not exist "%GTA%GTAIV.exe" (
  echo ERROR: Put this BAT beside GTAIV.exe.
  pause
  exit /b 1
)

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%I"
set "DEST=%PARENT%\GTAIV_DLAA_WORKING_BACKUP_%STAMP%"

mkdir "%DEST%" >nul 2>&1
mkdir "%DEST%\plugins" >nul 2>&1
mkdir "%DEST%\.trex" >nul 2>&1

echo Backing up root integration files...
for %%F in (d3d9.dll d3d9Hooked.dll dxvk.conf commandline.txt dinput8.dll) do (
  if exist "%GTA%%%F" copy /Y "%GTA%%%F" "%DEST%\%%F" >nul
)

echo Backing up FusionFix config...
for %%F in ("%GTA%plugins\*FusionFix*.asi" "%GTA%plugins\*FusionFix*.cfg" "%GTA%plugins\*FusionFix*.ini") do (
  if exist "%%~F" copy /Y "%%~F" "%DEST%\plugins\" >nul
)

echo Backing up bridge/ReShade/DLAA/DFC files...
for %%F in (
  NvRemixBridge.exe d3d9vk_x64.dll bridge.conf ReShade.ini ReShadePreset.ini
  dlss5-feed.addon64 dlss5-feed.cfg nvngx_dlss.dll nvngx_dlssnr.dll
  deep-fried-chicken.addon64 deep-fried-chicken-nvngx.dll deep-fried-chicken.cfg
) do (
  if exist "%GTA%.trex\%%F" copy /Y "%GTA%.trex\%%F" "%DEST%\.trex\%%F" >nul
)

if exist "%GTA%.trex\reshade-shaders" xcopy "%GTA%.trex\reshade-shaders" "%DEST%\.trex\reshade-shaders\" /E /I /Y /Q >nul

(
  echo GTA IV DLAA / DLSS5 integration backup
  echo Created: %DATE% %TIME%
  echo Source: %GTA%
  echo.
  echo This is NOT a full game backup. It contains integration/configuration files only.
  echo ReShade's global Vulkan layer under C:\ProgramData\ReShade is not included.
) > "%DEST%\README_RESTORE.txt"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$root='%DEST%'; Get-ChildItem -LiteralPath $root -Recurse -File ^| Where-Object {$_.Name -ne 'SHA256SUMS.txt'} ^| ForEach-Object { $h=Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash, $_.FullName.Substring($root.Length+1) } ^| Set-Content -LiteralPath (Join-Path $root 'SHA256SUMS.txt') -Encoding ASCII"

echo.
echo Backup complete:
echo   %DEST%
pause
