@echo off
setlocal
set "NAME=%~n0"
set "NAME=%NAME:build_pdf-=%"
set "IMG_WIDTH=25%%"
call "%~dp0build_pdf-all.bat" "%NAME%"
endlocal & exit /b %ERRORLEVEL%
