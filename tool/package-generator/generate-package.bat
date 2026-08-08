@echo off

cd /d %~dp0

set "BATCH_NAME=%~nx0"
echo ==================================================
echo %BATCH_NAME% 開始：%date% %time%
echo ==================================================

call clients\set-env.bat
set "SAVED_DOWNLOAD_ENABLED=%DOWNLOAD_ENABLED%"
set "SAVED_GENERATE_ENABLED=%GENERATE_ENABLED%"
set "SAVED_UPLOAD_ENABLED=%UPLOAD_ENABLED%"

:parse_args
if "%~1"=="" goto args_done
set "arg=%~1"
if /i "%arg:~0,7%"=="client=" set "CLIENT_NAME=%arg:~7%"
if /i "%arg:~0,8%"=="include=" set "GENERATE_SHEETS_INCLUDE=%arg:~8%"
if /i "%arg:~0,8%"=="exclude=" set "GENERATE_SHEETS_EXCLUDE=%arg:~8%"
shift
goto parse_args
:args_done
if defined CLIENT_NAME if exist "clients\set-env-%CLIENT_NAME%.bat" call clients\set-env-%CLIENT_NAME%.bat
set "DOWNLOAD_ENABLED=%SAVED_DOWNLOAD_ENABLED%"
set "GENERATE_ENABLED=%SAVED_GENERATE_ENABLED%"
set "UPLOAD_ENABLED=%SAVED_UPLOAD_ENABLED%"

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File .\scripts\generate-package.ps1
set "EXITCODE=%ERRORLEVEL%"

echo 5秒後に自動的に閉じます...
timeout /t 5 >nul

exit /b %EXITCODE%
