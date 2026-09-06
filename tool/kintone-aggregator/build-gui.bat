@echo off

cd /d %~dp0

powershell -ExecutionPolicy Bypass -File .\bats\build-gui.ps1
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo ÉrÉãÉhÇ…é∏îsÇµÇ‹ÇµÇΩÅB
)

exit /b %EXITCODE%