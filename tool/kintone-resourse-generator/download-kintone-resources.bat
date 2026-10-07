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

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bats\download-kintone-resources.ps1" -BaseUrl "%KINTONE_BASE_URL%" -DownloadRoot "%COMMON_DOWNLOAD_PATH%" -LogRoot "%COMMON_LOG_PATH%" -KintoneLogin "%KINTONE_LOGIN%" -KintonePassword "%KINTONE_PASSWORD%" -LogNamePrefix "%~n0" %*
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %~nx0"

exit /b %EXITCODE%