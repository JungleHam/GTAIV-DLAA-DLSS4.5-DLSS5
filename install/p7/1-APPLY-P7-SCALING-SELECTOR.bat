@echo off
setlocal
title GTA IV P7 - APPLY SCALING TECHNOLOGY SELECTOR
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P7-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
