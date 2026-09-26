@echo off
chcp 932 >nul
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

set "TargetDate="

for %%A in (%*) do (
    set "arg=%%~A"
    if "!arg:~0,1!"=="-" (
        set "arg=!arg:~1!"
        for /f "tokens=1* delims=:" %%K in ("!arg!") do (
            call set "%%K=%%L"
        )
    )
)

if "!TargetDate!"=="" (
    for /f %%i in ('powershell -NoProfile -Command "(Get-Date).AddDays(-1).ToString(\"yyyy-MM-dd\")"') do set "TargetDate=%%i"
)

if /i "!TargetDate!"=="now" (
    for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TargetDate=%%i"
)

for %%F in (
    "%~dp0bats\check-alert.bat"
    "%~dp0bats\post-alert-result.bat"
) do (
    call "%~dp0bats\message.bat" "Start %%~nxF {!TargetDate!}"
    
    call "%~dp0bats\message.bat" "Please wait..." "Green"
    
    call %%F -TargetDate:!TargetDate!
    
    call "%~dp0bats\message.bat" "Finished %%~nxF {!TargetDate!}"
)

endlocal