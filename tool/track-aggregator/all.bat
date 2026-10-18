@echo off
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

call "%~dp0bats\message.bat" "Start %MyName%"
echo.

call "%~dp0bats\message.bat" "Start excel-clean.bat"
call "%~dp0bats\message.bat" "Please wait..." "Green"
powershell -ExecutionPolicy Bypass -Command "Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -eq 0 | Stop-Process -Force"
call "%~dp0bats\message.bat" "Finished excel-clean.bat"

for %%F in (
    "%~dp0bats\download-results.bat"
    "%~dp0bats\collect-combine-result.bat"
    "%~dp0bats\collect-test-result.bat"
    "%~dp0bats\collect-survey-result.bat"
    "%~dp0bats\post-collect-results.bat"
) do (
    call "%~dp0bats\message.bat" "Start %%~nxF"
    
    call "%~dp0bats\message.bat" "Please wait..." "Green"
    
    call %%F
    
    call "%~dp0bats\message.bat" "Finished %%~nxF"
)

call "%~dp0bats\message.bat" "Finished %MyName%"

endlocal
