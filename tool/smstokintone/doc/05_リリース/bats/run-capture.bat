@echo off
setlocal
cd /d "%~dp0"
if "%DEVICE%"=="" set "DEVICE=emulator-5554"
set "MAESTRO=%USERPROFILE%\.maestro\bin\maestro.bat"
set "LIST=%*"
if "%LIST%"=="" set "LIST=send-settings app-settings continuation-info import-export top sms-search log"
for %%n in (%LIST%) do call :run %%n
pause
endlocal
goto :eof

:run
set "OUT=%TEMP%\capture-manual-%1"
if exist "%OUT%" rmdir /s /q "%OUT%"
call "%MAESTRO%" --device %DEVICE% test -e SETUP_FILE_PATTERN=env_base.* --debug-output "%OUT%" --flatten-debug-output capture-%1.yaml
echo %1 exit code %ERRORLEVEL%
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%OUT%' -Recurse -Filter *.png | Where-Object { $_.FullName -match 'takeScreenshot' } | Copy-Item -Destination '..\screenshots' -Force"
goto :eof
