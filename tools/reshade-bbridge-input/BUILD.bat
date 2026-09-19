@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "BUILT=%~dp0reshade-src\bin\x64\Release\ReShade64.dll"
set "PATCHED=%~dp0ReShade64-bbridge.dll"
set "BB_BUILT=%BUILT%"
set "BB_PATCHED=%PATCHED%"

echo ============================================================
echo ReShade 6.8.0 + b-bridge cross-process input patch
echo ============================================================
echo.

rem Never allow a failed build to leave an old DLL that looks current.
if exist "%PATCHED%" del /q "%PATCHED%"

where git >nul 2>nul || (
  echo ERROR: Git for Windows is not installed, or Windows cannot find it.
  echo.
  echo Install Git for Windows, then double-click BUILD.bat again.
  echo Project source: https://github.com/git-for-windows/git
  echo.
  echo Install Git, then double-click BUILD.bat again.
  pause
  exit /b 1
)
where python >nul 2>nul || (
  where py >nul 2>nul || (
    echo ERROR: Python 3 is not installed, or Windows cannot find it.
    echo.
    echo Install Python 3 and add it to PATH, then double-click BUILD.bat again.
    echo Python source project: https://github.com/python/cpython
    echo.
    echo During setup, enable the option to add Python to PATH, then double-click BUILD.bat again.
    pause
    exit /b 1
  )
)

if not exist "reshade-src\ReShade.sln" (
  echo [1/5] Cloning exact ReShade v6.8.0 source and submodules...
  git clone --depth 1 --branch v6.8.0 --recurse-submodules --shallow-submodules https://github.com/crosire/reshade.git reshade-src || goto :fail
) else (
  echo [1/5] Reusing existing reshade-src folder...
  git -C reshade-src submodule update --init --recursive --depth 1 || goto :fail
)

echo [2/5] Applying b-bridge input patch...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply_patch.ps1" "%~dp0reshade-src" || goto :fail

rem Verify the source really contains our patch before compiling.
findstr /C:"b-bridge cross-process input relay" "%~dp0reshade-src\source\input_windows.cpp" >nul || (
  echo ERROR: The patch script finished, but input_windows.cpp does not contain the b-bridge patch marker.
  echo Delete the reshade-src folder and run BUILD.bat again.
  goto :fail
)
findstr /C:"reshade_bridge_notify_ui_state" "%~dp0reshade-src\source\runtime_gui.cpp" >nul || (
  echo ERROR: The patch script finished, but runtime_gui.cpp does not contain the UI-state patch marker.
  echo Delete the reshade-src folder and run BUILD.bat again.
  goto :fail
)

echo [3/5] Finding Visual Studio / MSBuild...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo ERROR: Visual Studio 2022 Build Tools are required.
  echo.
  echo Install Visual Studio 2022 Build Tools from Microsoft.
  echo This repository intentionally stores no non-GitHub download link.
  echo.
  echo In the installer, select:
  echo   Desktop development with C++
  echo.
  echo Then double-click BUILD.bat again.
  pause
  exit /b 1
)
set "VSROOT="
for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT (
  echo ERROR: Visual Studio is installed, but the C++ build tools are missing.
  echo.
  echo Open Visual Studio Installer and add:
  echo   Desktop development with C++
  echo.
  echo Then double-click BUILD.bat again.
  pause
  exit /b 1
)
set "MSBUILD=%VSROOT%\MSBuild\Current\Bin\MSBuild.exe"
if not exist "%MSBUILD%" (
  echo ERROR: MSBuild was not found at:
  echo   "%MSBUILD%"
  echo.
  echo Repair or modify Visual Studio Build Tools, making sure Desktop development with C++ is installed.
  pause
  exit /b 1
)

echo [4/5] CLEAN rebuilding ReShade x64 Release...
"%MSBUILD%" "%~dp0reshade-src\ReShade.sln" /t:Rebuild /m /p:Configuration=Release /p:Platform="64-bit" /v:minimal || goto :fail

if not exist "%BUILT%" (
  echo ERROR: Build reported success but ReShade64.dll was not found.
  goto :fail
)

echo [5/5] Verifying the compiled DLL contains the b-bridge patch...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:BB_BUILT;$s=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($p));if($s.IndexOf('b-bridge input relay') -lt 0){Write-Host 'ERROR: compiled ReShade64.dll does NOT contain the b-bridge input patch marker.' -ForegroundColor Red;exit 91}" || goto :fail

copy /y "%BUILT%" "%PATCHED%" >nul || goto :fail
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:BB_PATCHED;$s=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($p));if($s.IndexOf('b-bridge input relay') -lt 0){exit 92}" || goto :fail

echo.
echo ============================================================
echo BUILD SUCCESS - PATCH MARKER VERIFIED
echo ============================================================
echo   %PATCHED%
echo.
echo Next: close this window and DOUBLE-CLICK INSTALL.bat.
echo INSTALL.bat asks for your GTA IV folder and requests Administrator permission itself.
echo No terminal commands are required.
echo.
pause
exit /b 0

:fail
if exist "%PATCHED%" del /q "%PATCHED%" >nul 2>nul
echo.
echo BUILD FAILED. No installable ReShade64-bbridge.dll has been left behind.
echo Scroll up for the first error.
echo If you are unsure what it means, copy the error text when asking for help.
pause
exit /b 1
