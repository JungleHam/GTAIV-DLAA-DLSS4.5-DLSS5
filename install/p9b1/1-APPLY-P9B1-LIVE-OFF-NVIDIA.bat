@echo off
setlocal
title GTA IV P9B.1 - APPLY LIVE OFF-NVIDIA TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P9B1-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
