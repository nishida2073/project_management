@echo off
cd /d %~dp0

call clients\set-env.bat

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\generate-config-from-template.ps1" %*
set "EXITCODE=%ERRORLEVEL%"

exit /b %EXITCODE%
