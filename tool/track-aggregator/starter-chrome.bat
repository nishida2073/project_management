@echo off

set "MyName=%~nx0"

pushd "%~dp0"

call .\bats\message.bat "Start %MyName%"

call .\bats\message.bat "Please wait..." "Green"

call .\bats\common-env.bat

set "ChromeExePath=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not exist "%ChromeExePath%" set "ChromeExePath=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"

start "" "%ChromeExePath%" "%TrackLoginUrl%"

call .\bats\message.bat "Finished %%~nxF"

popd

