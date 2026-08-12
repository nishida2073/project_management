@echo off

powershell -ExecutionPolicy Bypass -Command "Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -eq 0 | Stop-Process -Force"
