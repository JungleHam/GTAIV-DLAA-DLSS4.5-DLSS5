@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo ReShade 6.8.0 + b-bridge cross-process input patch
echo ============================================================
echo.

where git >nul 2>nul || (
  echo ERROR: Git is not installed or is not in PATH.
  pause
  exit /b 1
)
where python >nul 2>nul || (
  where py >nul 2>nul || (
    echo ERROR: Python is required by ReShade's glad dependency.
    pause
    exit /b 1
  )
)

if not exist "reshade-src\ReShade.sln" (
  echo [1/4] Cloning exact ReShade v6.8.0 source and submodules...
  git clone --depth 1 --branch v6.8.0 --recurse-submodules --shallow-submodules https://github.com/crosire/reshade.git reshade-src || goto :fail
) else (
  echo [1/4] Reusing existing reshade-src folder...
  git -C reshade-src submodule update --init --recursive --depth 1 || goto :fail
)

echo [2/4] Applying b-bridge input patch...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply_patch.ps1" "%~dp0reshade-src" || goto :fail

echo [3/4] Finding Visual Studio / MSBuild...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo ERROR: Visual Studio 2022 or Build Tools with Desktop development with C++ is required.
  pause
  exit /b 1
)
set "VSROOT="
for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT (
  echo ERROR: MSVC C++ build tools were not found.
  pause
  exit /b 1
)
set "MSBUILD=%VSROOT%\MSBuild\Current\Bin\MSBuild.exe"
if not exist "%MSBUILD%" (
  echo ERROR: MSBuild not found at "%MSBUILD%"
  pause
  exit /b 1
)

echo [4/4] Building ReShade x64 Release with full add-on support...
"%MSBUILD%" "%~dp0reshade-src\ReShade.sln" /m /p:Configuration=Release /p:Platform="64-bit" /v:minimal || goto :fail

if not exist "%~dp0reshade-src\bin\x64\Release\ReShade64.dll" (
  echo ERROR: Build reported success but ReShade64.dll was not found.
  pause
  exit /b 1
)
copy /y "%~dp0reshade-src\bin\x64\Release\ReShade64.dll" "%~dp0ReShade64-bbridge.dll" >nul

echo.
echo SUCCESS:
echo   %~dp0ReShade64-bbridge.dll
echo.
echo Next run INSTALL.bat from an Administrator terminal.
pause
exit /b 0

:fail
echo.
echo BUILD FAILED. Scroll up for the first error.
pause
exit /b 1
