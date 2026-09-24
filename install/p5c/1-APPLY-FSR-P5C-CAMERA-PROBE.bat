@echo off
setlocal
title GTA IV FSR P5C - APPLY SERVER-ONLY CAMERA PROBE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P5C-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
