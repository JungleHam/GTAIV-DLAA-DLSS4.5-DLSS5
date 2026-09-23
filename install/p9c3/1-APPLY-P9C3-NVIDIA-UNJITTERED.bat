@echo off
setlocal
title GTA IV P9C.3 - APPLY NVIDIA UNJITTERED TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P9C3-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
