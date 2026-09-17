@echo off
call "%~dp0clients\set-env.bat"

call "%~dp0bats\message.bat" "Start %~nx0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bats\check-kintone-resources.ps1" -BaseUrl "%KINTONE_BASE_URL%" -ConfigRoot "%COMMON_CONFIG_PATH%" -OutputRoot "%COMMON_CHECK_OUTPUT_PATH%" -LogRoot "%COMMON_LOG_PATH%" -KintoneLogin "%KINTONE_LOGIN%" -KintonePassword "%KINTONE_PASSWORD%" %*
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %~nx0"

exit /b %EXITCODE%