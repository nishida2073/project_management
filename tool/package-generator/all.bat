@echo off

set "BATCH_NAME=%~nx0"

:parse_args
if "%~1"=="" goto args_done
set "arg=%~1"
if /i "%arg:~0,7%"=="client=" set "CLIENT_NAME=%arg:~7%"
shift
goto parse_args
:args_done
call "%~dp0clients\set-env.bat"
if defined CLIENT_NAME if exist "%~dp0clients\set-env-%CLIENT_NAME%.bat" call "%~dp0clients\set-env-%CLIENT_NAME%.bat"

call "%~dp0bats\message.bat" "Start %BATCH_NAME%"

if "%DOWNLOAD_ENABLED%"=="1" (
    call "%~dp0download-folder.bat"
    if errorlevel 1 goto :error
)

if "%GENERATE_ENABLED%"=="1" (
    call "%~dp0generate-package.bat"
    if errorlevel 1 goto :error
)

if "%UPLOAD_ENABLED%"=="1" (
    call "%~dp0upload-folder.bat"
    if errorlevel 1 goto :error
)

call "%~dp0bats\message.bat" "Finished %BATCH_NAME%"
goto :eof

:error
call "%~dp0bats\message.bat" "Finished %BATCH_NAME% (failed)" "Red"
echo.
echo èàóùÇ™é∏îsÇµÇΩÇΩÇﬂíÜífÇµÇ‹ÇµÇΩÅB
exit /b 1

