@echo off
if "%DEVICE%"=="" set "DEVICE=emulator-5554"
if "%AVD%"=="" set "AVD=Pixel_6"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0export-avd.ps1" -Device "%DEVICE%" -Avd "%AVD%" %*
