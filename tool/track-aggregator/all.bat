@echo off
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

pushd "%~dp0"

set "LOG_DIR=.\logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

call .\bats\message.bat "Start %MyName%"
echo.


for %%F in (
    ".\bats\excel-clean.bat"
    ".\bats\collect-test-result.bat"
    ".\bats\collect-survey-result.bat"
    ".\bats\collect-combine-result.bat"
) do (
    call .\bats\message.bat "Start %%~nxF"
    
    call .\bats\message.bat "Please wait..." "Green"
    
    call "%%F" > "%LOG_DIR%\%%~nF-log.txt"
    
    call .\bats\message.bat "Finished %%~nxF"
)

popd

endlocal
