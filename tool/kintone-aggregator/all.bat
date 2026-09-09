@echo off
chcp 932 >nul
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

call "%~dp0bats\excel-clean.bat"

call "%~dp0bats\common-env.bat"

call "%~dp0bats\message.bat" "Start %MyName%"
echo.

call "%~dp0create-app-data.bat" "%~1" "%~2"

call "%~dp0collect-app-data.bat" "%~1" "%~2"
call "%~dp0check-alert.bat" "%~1"

call "%~dp0bats\message.bat" "Finished %MyName%"
echo.

endlocal
