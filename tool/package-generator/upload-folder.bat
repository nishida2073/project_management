@echo off

cd /d %~dp0

set "BATCH_NAME=%~nx0"
echo ==================================================
echo %BATCH_NAME% 開始：%date% %time%
echo ==================================================

:parse_args
if "%~1"=="" goto args_done
set "arg=%~1"
if /i "%arg:~0,7%"=="client=" set "CLIENT_NAME=%arg:~7%"
shift
goto parse_args
:args_done
call clients\set-env.bat
if defined CLIENT_NAME if exist "clients\set-env-%CLIENT_NAME%.bat" call clients\set-env-%CLIENT_NAME%.bat

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File .\scripts\upload-folder.ps1
set "EXITCODE=%ERRORLEVEL%"

echo ==================================================
echo %BATCH_NAME% 終了：%date% %time%
echo ==================================================

timeout /t 5 >nul

exit /b %EXITCODE%
