@echo off
setlocal enabledelayedexpansion

call "%~dp0bats\common.bat"

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

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bats\generate-config-from-template.ps1" -BaseTemplateRoot "%CommonBaseTemplatePath%" -CustomTemplateRoot "%CommonCustomTemplatePath%" -ConfigRoot "%CommonConfigPath%" -DownloadRoot "%CommonDownloadPath%" -LogRoot "%CommonLogPath%" -LogNamePrefix "%~n0" -BaseTemplateConfigName "%BaseTemplateConfigName%" -CustomTemplateConfigName "%CustomTemplateConfigName%" -DownloadConfigName "%DownloadConfigName%" -TargetGroupName "%TargetGroupName%"
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %~nx0"

exit /b %EXITCODE%
