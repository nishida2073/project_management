@echo off

cd /d %~dp0

call set-env.bat

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File .\scripts\download-folder.ps1
set "EXITCODE=%ERRORLEVEL%"

echo 5•bŒã‚ÉŽ©“®“I‚É•Â‚¶‚Ü‚·...
timeout /t 5 >nul

exit /b %EXITCODE%
