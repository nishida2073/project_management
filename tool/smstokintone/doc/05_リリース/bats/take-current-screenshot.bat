@echo off
setlocal
cd /d "%~dp0"
if "%DEVICE%"=="" set "DEVICE=emulator-5554"
set "MAESTRO=%USERPROFILE%\.maestro\bin\maestro.bat"
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%t"
set "FLOW=%TEMP%\now-%TS%.yaml"
set "OUT=%TEMP%\now-%TS%-out"
set "DEST=%~dp0..\current-state"
if not exist "%DEST%" mkdir "%DEST%"
> "%FLOW%" echo appId: jp.co.nttdata_univ.smstokintone
>> "%FLOW%" echo ---
>> "%FLOW%" echo - takeScreenshot: %TS%
call "%MAESTRO%" --device %DEVICE% test --debug-output "%OUT%" --flatten-debug-output "%FLOW%"
echo exit code %ERRORLEVEL%
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%OUT%' -Recurse -Filter '%TS%.png' | Copy-Item -Destination '%DEST%' -Force"
del "%FLOW%"
echo saved to %DEST%
endlocal
