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

if not exist "standalone" mkdir "standalone"
del /q "standalone\NvRemixBridge.exe" "standalone\*.obj" "standalone\dlfg_probe_standalone_ci.cpp" 2>nul

rem The source originally opened a Unicode-oriented CRT stream (ccs=UTF-8)
rem and then wrote to it with narrow vfprintf. MSVC treats that as an invalid
rem parameter and fast-fails with 0xC0000409 before the first log line. Build
rem a corrected temporary source using a normal binary stream for narrow logs.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText('standalone\dlfg_probe_standalone.cpp'); $s=$s.Replace('L\"w, ccs=UTF-8\"','L\"wb\"'); [IO.File]::WriteAllText('standalone\dlfg_probe_standalone_ci.cpp',$s,[Text.UTF8Encoding]::new($false))" || exit /b 45

cl /nologo /std:c++20 /EHsc /O2 /MD /FIcstdarg ^
  /I"deps\dlss\include" ^
  /I"deps\vulkan\include" ^
  "standalone\dlfg_probe_standalone_ci.cpp" ^
  /link /LIBPATH:"deps\dlss\lib\Windows_x86_64\x64" nvsdk_ngx_d.lib ^
  user32.lib advapi32.lib version.lib gdi32.lib ^
  /OUT:"standalone\NvRemixBridge.exe"
set "RC=%ERRORLEVEL%"
del /q "standalone\dlfg_probe_standalone_ci.cpp" 2>nul
if not "%RC%"=="0" exit /b %RC%
if not exist "standalone\NvRemixBridge.exe" exit /b 51
exit /b 0
