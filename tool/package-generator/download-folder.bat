@echo off

cd /d %~dp0

set "BATCH_NAME=%~nx0"
echo ==================================================
echo %BATCH_NAME% 開始：%date% %time%
echo ==================================================

call set-env.bat

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File .\scripts\download-folder.ps1
set "EXITCODE=%ERRORLEVEL%"

echo 5秒後に自動的に閉じます...
timeout /t 5 >nul

exit /b %EXITCODE%
