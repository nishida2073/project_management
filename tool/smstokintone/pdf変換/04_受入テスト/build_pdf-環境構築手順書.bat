@echo off
setlocal
set "NAME=%~n0"
set "NAME=%NAME:build_pdf-=%"
call "%~dp0build_pdf-all.bat" "%NAME%"
endlocal & exit /b %ERRORLEVEL%
