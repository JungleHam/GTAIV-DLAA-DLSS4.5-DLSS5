@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" exit /b 10
set "VSROOT="
for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT exit /b 11
call "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 12

if not exist deps mkdir deps

if not exist "deps\reshade\include\reshade.hpp" (
  git init -q "deps\reshade" || exit /b 20
  git -C "deps\reshade" remote add origin https://github.com/crosire/reshade.git
  git -C "deps\reshade" fetch --depth 1 origin 18deaa52de0c425a78b329e9cb3c497281cd00ec || exit /b 21
  git -C "deps\reshade" checkout -q FETCH_HEAD || exit /b 22
)
if not exist "deps\dlss\include\nvsdk_ngx_defs_dlssg.h" (
  git init -q "deps\dlss" || exit /b 30
  git -C "deps\dlss" remote add origin https://github.com/NVIDIA/DLSS.git
  git -C "deps\dlss" fetch --depth 1 origin 374959484e79a640feaba44c93ac8cfb0a03f5b5 || exit /b 31
  git -C "deps\dlss" checkout -q FETCH_HEAD || exit /b 32
)
if not exist "deps\vulkan\include\vulkan\vulkan.h" (
  git init -q "deps\vulkan" || exit /b 40
  git -C "deps\vulkan" remote add origin https://github.com/KhronosGroup/Vulkan-Headers.git
  git -C "deps\vulkan" fetch --depth 1 origin ee2ec5fd83dafce291024683b50dc89219333076 || exit /b 41
  git -C "deps\vulkan" checkout -q FETCH_HEAD || exit /b 42
)

del /q "dlfg-probe.addon64" "dlfg_probe_addon.obj" "dlfg-probe.lib" "dlfg-probe.exp" 2>nul

cl /nologo /std:c++20 /EHsc /O2 /MD /LD ^
  /FIcstdarg /FIcstring ^
  /I"deps\reshade\include" ^
  /I"deps\dlss\include" ^
  /I"deps\vulkan\include" ^
  "dlfg_probe_addon.cpp" ^
  /link /LIBPATH:"deps\dlss\lib\Windows_x86_64\x64" nvsdk_ngx_d.lib ^
  user32.lib advapi32.lib version.lib ^
  /OUT:"dlfg-probe.addon64"
if errorlevel 1 exit /b 50
if not exist "dlfg-probe.addon64" exit /b 51
exit /b 0
