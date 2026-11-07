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
if "%~1"=="log" call :sms log-sms.json
if "%~1"=="sms-search" call :sms sms-search-sms.json
call "%MAESTRO%" --device %DEVICE% test -e SETUP_FILE_PATTERN=env_base.* --debug-output "%OUT%" --flatten-debug-output capture-%1.yaml
echo %1 exit code %ERRORLEVEL%
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%OUT%' -Recurse -Filter *.png | Where-Object { $_.FullName -match 'takeScreenshot' } | Copy-Item -Destination '..\screenshots' -Force"
goto :eof

:sms
for /d %%d in ("%~dp0..\..\03_*") do start "" /B powershell -NoProfile -ExecutionPolicy Bypass -File "%%d\test-data\sms\load-inbox.ps1" -Device %DEVICE% -Json "%~dp0%1" -DelaySeconds 90
goto :eof
