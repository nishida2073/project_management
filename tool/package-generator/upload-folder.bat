@echo off

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
call "%~dp0clients\template\set-env.bat"
if defined CLIENT_NAME if exist "%~dp0clients\set-env-%CLIENT_NAME%.bat" call "%~dp0clients\set-env-%CLIENT_NAME%.bat"

call "%~dp0bats\message.bat" "Start %BATCH_NAME%"

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File "%~dp0bats\upload-folder.ps1" -SiteUrl "%UPLOAD_SITE_URL%" -SitePath "%UPLOAD_SITE_PATH%" -TenantId "%UPLOAD_SITE_TENANT_ID%" -LocalPath "%UPLOAD_LOCAL_PATH%" -LogPath "%COMMON_LOG_PATH%" -LogPrefix "%UPLOAD_LOG_PREFIX%" -ItemsInclude "%UPLOAD_ITEMS_INCLUDE%" -ItemsExclude "%UPLOAD_ITEMS_EXCLUDE%" -ClientName "%CLIENT_NAME%"
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %BATCH_NAME%"


exit /b %EXITCODE%
