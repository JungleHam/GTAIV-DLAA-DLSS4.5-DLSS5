@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo === b-bridge Input POC build ===

echo [1/3] Getting ReShade 6.8.0 headers...
if not exist "reshade\include\reshade.hpp" (
    where git >nul 2>nul || (
        echo ERROR: Git is not installed or not in PATH.
        pause
        exit /b 1
    )
    git clone --depth 1 --branch v6.8.0 https://github.com/crosire/reshade.git reshade || (
        echo ERROR: Could not clone ReShade.
        pause
        exit /b 1
    )
)

echo [2/3] Finding Visual Studio C++ Build Tools...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: Visual Studio 2022 or Build Tools with Desktop C++ is required.
    pause
    exit /b 1
)

set "VSROOT="
for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT (
    echo ERROR: MSVC x64 tools were not found.
    pause
    exit /b 1
)

call "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

echo [3/3] Compiling x64 ReShade add-on...
del /q bridge-input.addon64 bridge_input_addon.obj bridge-input.lib bridge-input.exp 2>nul

cl /nologo /std:c++20 /EHsc /O2 /LD /I"reshade\include" bridge_input_addon.cpp user32.lib /link /OUT:"bridge-input.addon64"
if errorlevel 1 (
    echo.
    echo BUILD FAILED.
    pause
    exit /b 1
)

del /q bridge_input_addon.obj bridge-input.lib bridge-input.exp 2>nul

echo.
echo SUCCESS: %CD%\bridge-input.addon64
pause
