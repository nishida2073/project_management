@echo off
call "%~dp0clients\set-env.bat"

call "%~dp0bats\message.bat" "Start %~nx0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bats\generate-config-from-template.ps1" -BaseTemplateRoot "%COMMON_BASE_TEMPLATE_PATH%" -CustomTemplateRoot "%COMMON_CUSTOM_TEMPLATE_PATH%" -ConfigRoot "%COMMON_CONFIG_PATH%" -DownloadRoot "%COMMON_DOWNLOAD_PATH%" -LogRoot "%COMMON_LOG_PATH%" %*
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %~nx0"

exit /b %EXITCODE%
