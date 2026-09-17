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

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File "%~dp0bats\download-folder.ps1" -SiteUrl "%DOWNLOAD_SITE_URL%" -SitePath "%DOWNLOAD_SITE_PATH%" -TenantId "%DOWNLOAD_SITE_TENANT_ID%" -LocalPath "%DOWNLOAD_LOCAL_PATH%" -LogPath "%COMMON_LOG_PATH%" -LogPrefix "%DOWNLOAD_LOG_PREFIX%" -ClientName "%CLIENT_NAME%"
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %BATCH_NAME%"



exit /b %EXITCODE%
