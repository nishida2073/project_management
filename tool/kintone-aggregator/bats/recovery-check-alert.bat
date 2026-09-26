@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0message.bat" "Start %MyName%"

call "%~dp0common-env.bat"

set "TargetDate="
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

call "%~dp0..\create-app-data.bat" -TargetDate:!TargetDate! -TargetGroupNameFilter:!TargetGroupNameFilter!
call "%~dp0..\collect-app-data.bat" -TargetDate:!TargetDate! -TargetGroupNameFilter:!TargetGroupNameFilter!

call "%~dp0message.bat" "Finished %MyName%"

endlocal