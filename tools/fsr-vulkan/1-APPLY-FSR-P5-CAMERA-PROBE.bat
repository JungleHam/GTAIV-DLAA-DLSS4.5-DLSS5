@echo off
setlocal
title GTA IV FSR P5 - APPLY CAMERA PROBE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P5-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
