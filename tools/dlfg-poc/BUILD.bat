@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo GTA IV DLFG POC - milestone 1.1 build
echo ============================================================
echo.

where git >nul 2>nul || (
  echo ERROR: Git for Windows is required.
  echo https://git-scm.com/install/windows
  pause
  exit /b 1
)

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo ERROR: Visual Studio 2022 Build Tools are required.
  echo https://aka.ms/vs/17/release/vs_BuildTools.exe
  echo Select: Desktop development with C++
  pause
  exit /b 1
)

set "VSROOT="
for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT (
  echo ERROR: MSVC x64 build tools were not found.
  echo Open Visual Studio Installer and add Desktop development with C++.
  pause
  exit /b 1
)

call "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

if not exist "deps" mkdir "deps"

if not exist "deps\reshade\include\reshade.hpp" (
  echo [1/4] Fetching pinned ReShade 6.8.0 source...
  git init -q "deps\reshade" || goto :fail
  git -C "deps\reshade" remote add origin https://github.com/crosire/reshade.git 2>nul
  git -C "deps\reshade" fetch --depth 1 origin 18deaa52de0c425a78b329e9cb3c497281cd00ec || goto :fail
  git -C "deps\reshade" checkout -q FETCH_HEAD || goto :fail
) else (
  echo [1/4] Reusing ReShade headers.
)

if not exist "deps\dlss\include\nvsdk_ngx_defs_dlssg.h" (
  echo [2/4] Fetching NVIDIA DLSS SDK 310.9.1...
  git init -q "deps\dlss" || goto :fail
  git -C "deps\dlss" remote add origin https://github.com/NVIDIA/DLSS.git 2>nul
  git -C "deps\dlss" fetch --depth 1 origin 374959484e79a640feaba44c93ac8cfb0a03f5b5 || goto :fail
  git -C "deps\dlss" checkout -q FETCH_HEAD || goto :fail
) else (
  echo [2/4] Reusing NVIDIA DLSS SDK.
)

if not exist "deps\vulkan\include\vulkan\vulkan.h" (
  echo [3/4] Fetching pinned Vulkan headers...
  git init -q "deps\vulkan" || goto :fail
  git -C "deps\vulkan" remote add origin https://github.com/KhronosGroup/Vulkan-Headers.git 2>nul
  git -C "deps\vulkan" fetch --depth 1 origin ee2ec5fd83dafce291024683b50dc89219333076 || goto :fail
  git -C "deps\vulkan" checkout -q FETCH_HEAD || goto :fail
) else (
  echo [3/4] Reusing Vulkan headers.
)

echo [4/4] Compiling x64 ReShade add-on...
del /q "dlfg-probe.addon64" "dlfg_probe_addon.obj" "dlfg-probe.lib" "dlfg-probe.exp" 2>nul

cl /nologo /std:c++20 /EHsc /O2 /MD /LD ^
  /FIcstdarg /FIcstring ^
  /I"deps\reshade\include" ^
  /I"deps\dlss\include" ^
  /I"deps\vulkan\include" ^
  "dlfg_probe_addon.cpp" ^
  /link /LIBPATH:"deps\dlss\lib\Windows_x86_64\x64" nvsdk_ngx_d.lib ^
  user32.lib advapi32.lib version.lib gdi32.lib ^
  /OUT:"dlfg-probe.addon64"

if errorlevel 1 goto :fail
if not exist "dlfg-probe.addon64" goto :fail

del /q "dlfg_probe_addon.obj" "dlfg-probe.lib" "dlfg-probe.exp" 2>nul

echo.
echo ============================================================
echo BUILD SUCCESS
echo ============================================================
echo %CD%\dlfg-probe.addon64
echo.
echo Next:
echo   1. Run GET-RUNTIME.bat once if nvngx_dlssg.dll is not here.
echo   2. Run INSTALL.bat.
echo.
pause
exit /b 0

:fail
echo.
echo BUILD FAILED. Copy the first compiler/linker error and send it back for the next iteration.
pause
exit /b 1
