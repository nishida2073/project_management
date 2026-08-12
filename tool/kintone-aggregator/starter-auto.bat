@echo off
chcp 932 >nul

pushd "%~dp0"

set "BATCH=all-multiple.bat"
call %BATCH%

popd
