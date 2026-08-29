@echo off

set "BATCH_NAME=%~nx0"
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

call "%~dp0clients\set-env.bat"
if exist "%~dp0clients\set-env-%CLIENT_NAME%.bat" call "%~dp0clients\set-env-%CLIENT_NAME%.bat"

call "%~dp0bats\message.bat" "Start %BATCH_NAME%"

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File "%~dp0bats\generate-config.ps1"
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %BATCH_NAME%"

:end
timeout /t 5 >nul

exit /b %EXITCODE%
