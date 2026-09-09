@echo off

set "envFile=%ClientDataRootDir%\%~1.bat"
if exist "%envFile%" goto :EOF

echo %~1| findstr /r ".*-[0-9][0-9][0-9][0-9]$" >nul
if errorlevel 1 goto :EOF

set "baseName=%~1"
set "baseName=%baseName:~0,-5%"
set "envFile=%ClientDataRootDir%\%baseName%.bat"
