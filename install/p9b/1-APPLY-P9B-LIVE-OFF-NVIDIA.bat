@echo off
setlocal
title GTA IV P9B - APPLY LIVE OFF-NVIDIA TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P9B-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
