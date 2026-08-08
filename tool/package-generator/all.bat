@echo off

cd /d %~dp0

:parse_args
if "%~1"=="" goto args_done
set "arg=%~1"
if /i "%arg:~0,7%"=="client=" set "CLIENT_NAME=%arg:~7%"
shift
goto parse_args
:args_done
call clients\set-env.bat
if defined CLIENT_NAME if exist "clients\set-env-%CLIENT_NAME%.bat" call clients\set-env-%CLIENT_NAME%.bat

if "%DOWNLOAD_ENABLED%"=="1" (
    call download-folder.bat
    if errorlevel 1 goto :error
)

if "%GENERATE_ENABLED%"=="1" (
    call generate-package.bat
    if errorlevel 1 goto :error
)

if "%UPLOAD_ENABLED%"=="1" (
    call upload-folder.bat
    if errorlevel 1 goto :error
)

goto :eof

:error
echo.
echo èàóùÇ™é∏îsÇµÇΩÇΩÇﬂíÜífÇµÇ‹ÇµÇΩÅB
exit /b 1

