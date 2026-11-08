@echo off
if "%DEVICE%"=="" set "DEVICE=emulator-5554"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0push-test-files.ps1" -Device "%DEVICE%" %*
