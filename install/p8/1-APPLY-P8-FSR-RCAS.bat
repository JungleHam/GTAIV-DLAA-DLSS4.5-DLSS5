@echo off
setlocal
title GTA IV P8 - APPLY AMD FSR RCAS TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P8-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.&pause
