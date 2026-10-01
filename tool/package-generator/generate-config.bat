@echo off
setlocal enabledelayedexpansion

set "BATCH_NAME=%~nx0"

call "%~dp0bats\common-env.bat"

for %%A in (%*) do (
    set "arg=%%~A"
    if "!arg:~0,1!"=="-" (
        set "arg=!arg:~1!"
        for /f "tokens=1* delims=:" %%K in ("!arg!") do (
            call set "%%K=%%L"
        )
    )
)
call "%~dp0clients\!ClientName!.bat"

call "%~dp0bats\message.bat" "Start %BATCH_NAME%"

set "LogPrefix=%~n0"

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File "%~dp0bats\generate-config.ps1" -SourcePath "!GenerateSourcePath!" -TargetConfigFilePath "!GenerateConfigPath!" -Force "!Force!" -LogPath "!CommonLogPath!" -LogPrefix "!LogPrefix!" -ClientName "!ClientName!"
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %BATCH_NAME%"

:end

exit /b %EXITCODE%
