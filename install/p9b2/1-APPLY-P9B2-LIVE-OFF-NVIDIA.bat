@echo off
setlocal
title GTA IV P9B.2 - APPLY LIVE OFF-NVIDIA SR TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P9B2-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
