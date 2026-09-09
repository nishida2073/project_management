@echo off

set "MyName=%~nx0"

call "%~dp0bats\message.bat" "Start %MyName%"

call "%~dp0bats\message.bat" "Please wait..." "Green"

call "%~dp0bats\common-env.bat"

set "ChromeExePath=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not exist "%ChromeExePath%" set "ChromeExePath=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"

start "" "%ChromeExePath%" "%TrackLoginUrl%"

call "%~dp0bats\message.bat" "Finished %MyName%"

