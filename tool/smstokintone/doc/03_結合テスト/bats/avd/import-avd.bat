@echo off
if "%AVD%"=="" set "AVD=Pixel_6"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0import-avd.ps1" -Avd "%AVD%" %*
