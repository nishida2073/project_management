@echo off

set "BATCH_NAME=%~nx0"
call "%~dp0clients\template\set-env.bat"

:parse_args
if "%~1"=="" goto args_done
set "arg=%~1"
if /i "%arg:~0,7%"=="client=" set "CLIENT_NAME=%arg:~7%"
if /i "%arg:~0,8%"=="include=" set "GENERATE_SHEETS_INCLUDE=%arg:~8%"
if /i "%arg:~0,8%"=="exclude=" set "GENERATE_SHEETS_EXCLUDE=%arg:~8%"
shift
goto parse_args
:args_done
if defined CLIENT_NAME if exist "%~dp0clients\set-env-%CLIENT_NAME%.bat" call "%~dp0clients\set-env-%CLIENT_NAME%.bat"

call "%~dp0bats\message.bat" "Start %BATCH_NAME%"

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File "%~dp0bats\generate-package.ps1" -ConfigPath "%GENERATE_CONFIG_PATH%" -WorkPath "%GENERATE_WORK_PATH%" -OutputPath "%GENERATE_OUTPUT_PATH%" -LogPath "%COMMON_LOG_PATH%" -LogPrefix "%GENERATE_LOG_PREFIX%" -SheetsInclude "%GENERATE_SHEETS_INCLUDE%" -SheetsExclude "%GENERATE_SHEETS_EXCLUDE%" -SourcePath "%GENERATE_SOURCE_PATH%" -ClientName "%CLIENT_NAME%"
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %BATCH_NAME%"


exit /b %EXITCODE%
