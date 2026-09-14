@echo off
setlocal EnableExtensions
set "FEEDER=%~1"
set "NGX=%~2"
set "VULKAN=%~3"
set "OUT=%~4"
set "OBJ=%~5"
set "M3K=%~dp0"
call "%FEEDER%\tools\vcvars.bat" x64 || exit /b 1
pushd "%FEEDER%" || exit /b 1
rc /nologo /fo "%OBJ%\version.res" src\version.rc || goto :fail
cl /nologo /LD /EHsc /O2 /MD /W3 /std:c++20 /I"%M3K%src" /Iexternal\reshade\include /I"%NGX%\include" /I"%VULKAN%\include" /Iexternal\imgui /Iexternal\minhook\include /Fo"%OBJ%\\" /Fd"%OBJ%\feeder.pdb" src\dlss5-feed.cpp external\minhook\src\buffer.c external\minhook\src\hook.c external\minhook\src\trampoline.c external\minhook\src\hde\hde64.c /link /OUT:"%OUT%\dlss5-feed.addon64" /IMPLIB:"%OBJ%\feeder.lib" "%OBJ%\version.res" "%NGX%\lib\Windows_x86_64\x64\nvsdk_ngx_d.lib" version.lib kernel32.lib user32.lib advapi32.lib ole32.lib || goto :fail
cl /nologo /LD /EHsc /O2 /MT /W4 /std:c++20 /Fo"%OBJ%\m3k_bridge.obj" "%M3K%src\m3k_bridge.cpp" /link /OUT:"%OUT%\m3k\m3k-nvngx.dll" /IMPLIB:"%OBJ%\m3k-bridge.lib" || goto :fail
cl /nologo /EHsc /O2 /MT /W4 /std:c++20 /I"%NGX%\include" /Fo"%OBJ%\m3k_tests.obj" "%M3K%tests\m3k_tests.cpp" /link /OUT:"%OUT%\m3k-tests.exe" || goto :fail
popd
exit /b 0
:fail
popd
exit /b 1
