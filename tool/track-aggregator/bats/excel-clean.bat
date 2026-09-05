@echo off

set "MyName=%~nx0"

call "%~dp0message.bat" "Start %MyName%"

powershell -ExecutionPolicy Bypass -Command "Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -eq 0 | Stop-Process -Force"

call "%~dp0message.bat" "Finished %MyName%"
