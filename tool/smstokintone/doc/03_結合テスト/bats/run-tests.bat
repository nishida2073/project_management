@echo off
if "%DEVICE%"=="" set "DEVICE=emulator-5554"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-tests.ps1" -Device "%DEVICE%" %*
set "EXIT_CODE=%ERRORLEVEL%"
pause
exit /b %EXIT_CODE%
