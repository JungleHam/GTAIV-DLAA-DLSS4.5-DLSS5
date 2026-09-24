@echo off
setlocal
title GTA IV P9A - APPLY LIVE AMD-OFF TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P9A-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
