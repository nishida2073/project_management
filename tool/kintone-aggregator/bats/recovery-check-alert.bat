@echo off

pushd "%~dp0"

call ".\common-env.bat"

call "..\create-app-data.bat" "%~1" "" "%~2"
call "..\collect-app-data-ps.bat" "%~1" "" "%~2"

popd

