@echo off
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

for %%F in (
    ".\bats\check-alert-ps.bat"
) do (
    call ".\bats\message.bat" "Start %%~nxF {%TargetDate%}"
    
    call ".\bats\message.bat" "Please wait..." "Green"
    
    call "%%F" "%TargetDate%" > "%LOG_DIR%\%%~nF-%TargetDate%-log.txt"
    
    call ".\bats\message.bat" "Finished %%~nxF {%TargetDate%}"
)

endlocal
