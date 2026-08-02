@echo off

cd /d %~dp0

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File .\GeneratePackage.ps1

pause