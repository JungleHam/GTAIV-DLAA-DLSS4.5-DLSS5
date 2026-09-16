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
set "DEST=%PARENT%\GTAIV_DLSS_WORKING_BACKUP_%STAMP%"

mkdir "%DEST%" >nul 2>&1
mkdir "%DEST%\plugins" >nul 2>&1
mkdir "%DEST%\.trex" >nul 2>&1
mkdir "%DEST%\.trex\m3k" >nul 2>&1

echo Backing up root integration files...
for %%F in (d3d9.dll d3d9Hooked.dll dxvk.conf commandline.txt dinput8.dll DLSS-Full-Control.bat DLSS_FULL_INSTALLED.txt) do (
  if exist "%GTA%%%F" copy /Y "%GTA%%%F" "%DEST%\%%F" >nul
)

echo Backing up FusionFix config...
for %%F in ("%GTA%plugins\*FusionFix*.asi" "%GTA%plugins\*FusionFix*.cfg" "%GTA%plugins\*FusionFix*.ini") do (
  if exist "%%~F" copy /Y "%%~F" "%DEST%\plugins\" >nul
)

echo Backing up bridge, ReShade, DLAA and DLSS integration files...
for %%F in (
  NvRemixBridge.exe d3d9vk_x64.dll bridge.conf ReShade.ini ReShadePreset.ini
  dlss5-feed.addon64 dlss5-feed.cfg nvngx_dlss.dll m3k-nr.ini
) do (
  if exist "%GTA%.trex\%%F" copy /Y "%GTA%.trex\%%F" "%DEST%\.trex\%%F" >nul
)

for %%F in (m3k-nvngx.dll nvngx_dlssnr.dll) do (
  if exist "%GTA%.trex\m3k\%%F" copy /Y "%GTA%.trex\m3k\%%F" "%DEST%\.trex\m3k\%%F" >nul
)

if exist "%GTA%.trex\reshade-shaders" xcopy "%GTA%.trex\reshade-shaders" "%DEST%\.trex\reshade-shaders\" /E /I /Y /Q >nul

(
  echo GTA IV DLAA / DLSS 4.5 SR / DLSS 5 NR integration backup
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
