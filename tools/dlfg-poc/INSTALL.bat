@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo GTA IV DLFG POC - IN-GAME INSTALLER RETIRED
echo ============================================================
echo.
echo Do NOT install milestone 1.1 into GTA IV.
echo.
echo Live testing showed that creating and shutting down a second NGX/Vulkan
 echo context inside NvRemixBridge.exe can destabilize the real DLAA/DLSS5
 echo session during the legal-screen to game swapchain transition.
echo.
echo If you previously installed the probe:
echo   1. Fully close GTA IV.
echo   2. Run UNINSTALL.bat.
echo.
echo For the next test use:
echo   RUN-STANDALONE.bat
 echo.
echo Milestone 1.2 runs in a separate process and does not touch the game.
echo.
pause
exit /b 1
