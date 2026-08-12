@echo off
chcp 932 >nul
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

pushd "%~dp0"

set "LOG_DIR=.\logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if "%~1"=="" (
    for /f %%i in ('powershell -NoProfile -Command "(Get-Date).AddDays(-1).ToString(\"yyyy-MM-dd\")"') do set "TargetDate=%%i"
) else if /i "%~1"=="now" (
    set "TargetDate=now"
) else (
    set "TargetDate=%~1"
)

if /i "%TargetDate%"=="now" (
    for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TargetDate=%%i"
)

if "%~2"=="" (
    set "TargetDateTerm=1"
) else (
    set "TargetDateTerm=%~2"
)

set /a Start=%TargetDateTerm%-1
for /l %%i in (%Start%,-1,0) do (
    for /f %%d in ('powershell -NoProfile -Command "(Get-Date \"%TargetDate%\").AddDays(-%%i).ToString(\"yyyy-MM-dd\")"') do (
        for %%F in (
            ".\bats\collect-app-data-ps.bat"
        ) do (
            call ".\bats\message.bat" "Start %%~nxF {%%d}"
            
            call ".\bats\message.bat" "Please wait..." "Green"
            
            call "%%F" "%%d" "%~3" > "%LOG_DIR%\%%~nF-%%d-log.txt"
            
            call ".\bats\message.bat" "Finished %%~nxF {%%d}"
        )
    )
)

endlocal
