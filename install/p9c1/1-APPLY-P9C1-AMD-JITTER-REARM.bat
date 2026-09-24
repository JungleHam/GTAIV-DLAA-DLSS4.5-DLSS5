@echo off
setlocal
title GTA IV P9C.1 - APPLY AMD JITTER RE-ARM TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P9C1-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
