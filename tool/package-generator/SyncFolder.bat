@echo off

cd /d %~dp0

call SetEnv.bat

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File .\SyncFolder.ps1

echo 5•bŒã‚ÉŽ©“®“I‚É•Â‚¶‚Ü‚·...
timeout /t 5 >nul