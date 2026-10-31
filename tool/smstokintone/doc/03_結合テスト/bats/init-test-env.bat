@echo off
setlocal
set "TEST=%~dp0.."
set "DEVICE_ARG="
if not "%~1"=="" set "DEVICE_ARG=-s %~1"
if not exist "%TEST%\test-data\settings\test-settings.json" (
    echo NG: test-data\settings\test-settings.json not found
    pause
    exit /b 1
)
adb %DEVICE_ARG% push "%TEST%\test-data\settings\test-settings.json" /sdcard/Download/s2k-test-settings.json
if errorlevel 1 (
    echo NG: failed to copy the settings file to the device
    pause
    exit /b 1
)
echo OK: test settings file was copied to /sdcard/Download/s2k-test-settings.json
pause
exit /b 0
