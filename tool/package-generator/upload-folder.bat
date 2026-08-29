@echo off

cd /d %~dp0

set "BATCH_NAME=%~nx0"
:parse_args
if "%~1"=="" goto args_done
set "arg=%~1"
if /i "%arg:~0,7%"=="client=" set "CLIENT_NAME=%arg:~7%"
if /i "%arg:~0,8%"=="include=" set "UPLOAD_ITEMS_INCLUDE=%arg:~8%"
if /i "%arg:~0,8%"=="exclude=" set "UPLOAD_ITEMS_EXCLUDE=%arg:~8%"
shift
goto parse_args
:args_done
call clients\set-env.bat
if defined CLIENT_NAME if exist "clients\set-env-%CLIENT_NAME%.bat" call clients\set-env-%CLIENT_NAME%.bat

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File .\scripts\upload-folder.ps1
set "EXITCODE=%ERRORLEVEL%"

timeout /t 5 >nul

exit /b %EXITCODE%
