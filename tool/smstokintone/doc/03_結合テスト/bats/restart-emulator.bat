@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-emulator.ps1" %*
