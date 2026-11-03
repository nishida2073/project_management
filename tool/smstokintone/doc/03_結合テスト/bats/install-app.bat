@echo off
setlocal
set DEVICE=%~1
if "%DEVICE%"=="" set DEVICE=emulator-5554
set APK=%~dp0..\..\..\app\build\outputs\apk\debug\s2k.apk
if not exist "%APK%" (echo APK not found: %APK% & exit /b 1)
adb -s %DEVICE% install -r "%APK%"
adb -s %DEVICE% shell pm list packages smstokintone
endlocal
