@echo off
setlocal enabledelayedexpansion

call "%~dp0common.bat"

for %%A in (%*) do (
    set "arg=%%~A"
    if "!arg:~0,1!"=="-" (
        set "arg=!arg:~1!"
        for /f "tokens=1* delims=:" %%K in ("!arg!") do (
            call set "%%K=%%L"
        )
    )
)

call "%~dp0..\clients\!TargetGroupName!.bat"

call "%~dp0message.bat" "Start %~nx0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0create-template.ps1" -KintoneBaseUrl "%KintoneBaseUrl%" -TemplateRoot "%BASE_PATH%template" -LogRoot "%CommonLogPath%" -KintoneLogin "%KintoneLoginName%" -KintonePassword "%KintonePassword%" -LogNamePrefix "%~n0" -OrgFileName "template.xlsx" -SpaceId "%SpaceId%" -TargetGroupName "%TargetGroupName%" -TemplateName "%TemplateName%"
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0message.bat" "Finished %~nx0"

exit /b %EXITCODE%