@echo off
setlocal enabledelayedexpansion

for %%A in (%*) do (
    set "arg=%%~A"
    if "!arg:~0,1!"=="-" (
        set "arg=!arg:~1!"
        for /f "tokens=1* delims=:" %%K in ("!arg!") do (
            call set "%%K=%%L"
        )
    )
)

call "%~dp0clients\!TargetGroupName!.bat"

call "%~dp0bats\message.bat" "Start %~nx0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bats\generate-config-from-template.ps1" -BaseTemplateRoot "%COMMON_BASE_TEMPLATE_PATH%" -CustomTemplateRoot "%COMMON_CUSTOM_TEMPLATE_PATH%" -ConfigRoot "%COMMON_CONFIG_PATH%" -DownloadRoot "%COMMON_DOWNLOAD_PATH%" -LogRoot "%COMMON_LOG_PATH%" -LogNamePrefix "%~n0" %*
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %~nx0"

exit /b %EXITCODE%
