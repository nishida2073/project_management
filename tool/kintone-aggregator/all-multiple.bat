@echo off
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

pushd "%~dp0"

call ".\bats\excel-clean.bat" "Start %MyName%"

call ".\bats\common-env.bat"

call ".\bats\message.bat" "Start %MyName%"
echo.

call ".\create-app-data.bat" "%~1" "%~2"

call ".\collect-app-data-ps.bat" "%~1" "%~2"
call ".\check-alert-ps.bat" "%~1"

call ".\bats\message.bat" "Finished %MyName%"
echo.

popd

endlocal
