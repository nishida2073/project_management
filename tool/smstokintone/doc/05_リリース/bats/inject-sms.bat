@echo off
setlocal
cd /d "%~dp0"
if "%DEVICE%"=="" set "DEVICE=emulator-5554"
set "JSON=%~1"
if "%JSON%"=="" set "JSON=test-sms.json"
for /d %%d in ("%~dp0..\..\03_*") do powershell -NoProfile -ExecutionPolicy Bypass -File "%%d\test-data\sms\load-inbox.ps1" -Device %DEVICE% -Json "%~dp0%JSON%" -DelaySeconds 90
echo done
pause
endlocal
