@echo off
chcp 932 >nul
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

call "%~dp0bats\excel-clean.bat"

call "%~dp0bats\common-env.bat"

call "%~dp0bats\message.bat" "Start %MyName%"
echo.

set "TargetDate="
set "TargetDateTerm="
set "TargetGroupNameFilter="

for %%A in (%*) do (
    set "arg=%%~A"
    if "!arg:~0,1!"=="-" (
        set "arg=!arg:~1!"
        for /f "tokens=1* delims=:" %%K in ("!arg!") do (
            call set "%%K=%%L"
        )
    )
)

call "%~dp0create-app-data.bat" -TargetDate:!TargetDate! -TargetDateTerm:!TargetDateTerm! -TargetGroupNameFilter:!TargetGroupNameFilter!

call "%~dp0collect-app-data.bat" -TargetDate:!TargetDate! -TargetDateTerm:!TargetDateTerm! -TargetGroupNameFilter:!TargetGroupNameFilter!
call "%~dp0check-and-post-alert.bat" -TargetDate:!TargetDate!

call "%~dp0bats\message.bat" "Finished %MyName%"
echo.

endlocal