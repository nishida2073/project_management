@echo off
call "%~dp0clients\set-env.bat"

call "%~dp0bats\message.bat" "Start %~nx0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bats\create-space-from-template.ps1" -BaseUrl "%KINTONE_BASE_URL%" -LogRoot "%COMMON_LOG_PATH%" -KintoneLogin "%KINTONE_LOGIN%" -KintonePassword "%KINTONE_PASSWORD%" %*
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %~nx0"

exit /b %EXITCODE%
