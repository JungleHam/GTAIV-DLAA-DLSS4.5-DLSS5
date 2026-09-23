@echo off
setlocal
title GTA IV P9C.4 - APPLY FULL-AA NVIDIA JITTER SIGN TEST
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FSR-P9C4-Apply.ps1" -GameDir "%~1"
if errorlevel 1 (echo.&echo APPLY FAILED.&pause&exit /b 1)
echo.
pause
