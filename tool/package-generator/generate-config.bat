@echo off

cd /d %~dp0

set "BATCH_NAME=%~nx0"
echo ==================================================
echo %BATCH_NAME% 開始：%date% %time%
echo ==================================================

set "FORCE="

:parse_args
if "%~1"=="" goto args_done
set "arg=%~1"
if /i "%arg:~0,7%"=="client:" set "CLIENT_NAME=%arg:~7%"
if /i "%arg:~0,6%"=="force:" set "FORCE=%arg:~6%"
shift
goto parse_args
:args_done

if not defined CLIENT_NAME (
    echo client:^<クライアント名^> を指定してください（例: generate-config.bat client:サンプル）
    set "EXITCODE=1"
    goto end
)

call clients\set-env.bat
if exist "clients\set-env-%CLIENT_NAME%.bat" call clients\set-env-%CLIENT_NAME%.bat

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File .\scripts\generate-config.ps1
set "EXITCODE=%ERRORLEVEL%"

:end
echo ==================================================
echo %BATCH_NAME% 終了：%date% %time%
echo ==================================================

timeout /t 5 >nul

exit /b %EXITCODE%