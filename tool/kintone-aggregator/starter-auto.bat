@echo off
chcp 932 >nul

pushd "%~dp0"

set "BATCH=all.bat"
call %BATCH%

popd
