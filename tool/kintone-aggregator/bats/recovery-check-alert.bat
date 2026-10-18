@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0message.bat" "Start %MyName%"

call "%~dp0common.bat"

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

if "!TargetDate!"=="" (
    for /f %%i in ('powershell -NoProfile -Command "(Get-Date).AddDays(-1).ToString(\"yyyy-MM-dd\")"') do set "TargetDate=%%i"
)

if /i "!TargetDate!"=="now" (
    for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TargetDate=%%i"
)

if "!TargetDateTerm!"=="" (
    set "TargetDateTerm=1"
)

set /a Start=!TargetDateTerm!-1
for /l %%i in (!Start!,-1,0) do (
    for /f %%d in ('powershell -NoProfile -Command "(Get-Date \"!TargetDate!\").AddDays(-%%i).ToString(\"yyyy-MM-dd\")"') do (
        for %%F in (
            "%~dp0create-daily-report.bat"
            "%~dp0create-pulse-survey.bat"
        ) do (
            call "%~dp0message.bat" "Start %%~nxF {%%d}"

            call "%~dp0message.bat" "Please wait..." "Green"

            call %%F -TargetDate:%%d -TargetGroupNameFilter:!TargetGroupNameFilter!

            call "%~dp0message.bat" "Finished %%~nxF {%%d}"
        )
    )
)

set /a Start=!TargetDateTerm!-1
for /l %%i in (!Start!,-1,0) do (
    for /f %%d in ('powershell -NoProfile -Command "(Get-Date \"!TargetDate!\").AddDays(-%%i).ToString(\"yyyy-MM-dd\")"') do (
        for %%F in (
            "%~dp0collect-app-data.bat"
        ) do (
            call "%~dp0message.bat" "Start %%~nxF {%%d}"

            call "%~dp0message.bat" "Please wait..." "Green"

            call %%F -TargetDate:%%d -TargetGroupNameFilter:!TargetGroupNameFilter!

            call "%~dp0message.bat" "Finished %%~nxF {%%d}"
        )
    )
)

call "%~dp0message.bat" "Finished %MyName%"

endlocal
