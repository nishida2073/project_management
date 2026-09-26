@echo off
chcp 932 >nul
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

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
            "%~dp0bats\collect-app-data.bat"
        ) do (
            call "%~dp0bats\message.bat" "Start %%~nxF {%%d}"
            
            call "%~dp0bats\message.bat" "Please wait..." "Green"
            
            call %%F -TargetDate:%%d -TargetGroupNameFilter:!TargetGroupNameFilter!
            
            call "%~dp0bats\message.bat" "Finished %%~nxF {%%d}"
        )
    )
)

endlocal