@echo off
setlocal
cd /d "%~dp0"
if "%DEVICE%"=="" set "DEVICE=emulator-5554"
set "MAESTRO=%USERPROFILE%\.maestro\bin\maestro.bat"
set "OUT=%TEMP%\capture-permission"
if exist "%OUT%" rmdir /s /q "%OUT%"
adb -s %DEVICE% push "%~dp0capture-env.json" /sdcard/Download/capture-env.json
call "%MAESTRO%" --device %DEVICE% test -e SETUP_FILE_PATTERN=capture-env.* --debug-output "%OUT%" --flatten-debug-output capture-permission.yaml
echo exit code %ERRORLEVEL%
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%OUT%' -Recurse -Filter *.png | Where-Object { $_.FullName -match 'takeScreenshot' } | Copy-Item -Destination '..\screenshots' -Force"
pause
endlocal
