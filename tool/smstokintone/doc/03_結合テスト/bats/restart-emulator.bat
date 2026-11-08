@echo off
if "%DEVICE%"=="" set "DEVICE=emulator-5554"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-emulator.ps1" -Device "%DEVICE%" %*
