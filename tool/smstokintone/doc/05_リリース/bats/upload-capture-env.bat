@echo off
setlocal
cd /d "%~dp0"
if "%DEVICE%"=="" set "DEVICE=emulator-5554"
adb -s %DEVICE% push "%~dp0capture-env.json" /sdcard/Download/capture-env.json
echo exit code %ERRORLEVEL%
pause
endlocal
