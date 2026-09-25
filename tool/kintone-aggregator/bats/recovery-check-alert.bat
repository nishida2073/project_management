@echo off

set "MyName=%~nx0"

call "%~dp0message.bat" "Start %MyName%"

call "%~dp0common-env.bat"

call "%~dp0..\create-app-data.bat" "%~1" "" "%~2"
call "%~dp0..\collect-app-data.bat" "%~1" "" "%~2"

call "%~dp0message.bat" "Finished %MyName%"

