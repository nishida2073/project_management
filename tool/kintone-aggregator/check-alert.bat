@echo off
chcp 932 >nul
setlocal EnableDelayedExpansion

set "MyName=%~nx0"

call "%~dp0bats\common-env.bat"

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
    "%~dp0bats\check-alert.bat"
) do (
    call "%~dp0bats\message.bat" "Start %%~nxF {%TargetDate%}"
    
    call "%~dp0bats\message.bat" "Please wait..." "Green"
    
    call %%F "%TargetDate%" > "%LOG_DIR%\%%~nF-%TargetDate%.log"
    
    call "%~dp0bats\message.bat" "Finished %%~nxF {%TargetDate%}"
)

endlocal
