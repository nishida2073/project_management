@echo off
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

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
    
    call %%F
    
    call "%~dp0bats\message.bat" "Finished %%~nxF"
)

call "%~dp0bats\message.bat" "Finished %MyName%"

endlocal
