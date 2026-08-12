@echo off
chcp 932 >nul
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

pushd "%~dp0"

call ".\bats\message.bat" "Start %MyName%"
echo.

call ".\create-app-data.bat" "%~1" "%~2"
call ".\collect-app-data-ps.bat" "%~1" "%~2"
call ".\check-alert-ps.bat" "%~1"

call ".\bats\message.bat" "Finished %MyName%"
echo.

popd

endlocal
