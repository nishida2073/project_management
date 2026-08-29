@echo off
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

set "LOG_DIR=%~dp0logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

call "%~dp0bats\message.bat" "Start %MyName%"
echo.


for %%F in (
    "%~dp0bats\excel-clean.bat"
    "%~dp0bats\download-results.bat"
    "%~dp0bats\collect-combine-result.bat"
    "%~dp0bats\collect-test-result.bat"
    "%~dp0bats\collect-survey-result.bat"
) do (
    call "%~dp0bats\message.bat" "Start %%~nxF"
    
    call "%~dp0bats\message.bat" "Please wait..." "Green"
    
    call %%F > "%LOG_DIR%\%%~nF.log"
    
    call "%~dp0bats\message.bat" "Finished %%~nxF"
)

call "%~dp0bats\message.bat" "Finished %MyName%"

endlocal
