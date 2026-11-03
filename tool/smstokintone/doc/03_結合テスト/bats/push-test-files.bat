@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0push-test-files.ps1" %*
