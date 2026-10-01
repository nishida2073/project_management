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
 -File "%~dp0bats\generate-package.ps1" -ConfigPath "!GenerateConfigPath!" -WorkPath "!GenerateWorkPath!" -OutputPath "!GenerateOutputPath!" -LogPath "!CommonLogPath!" -LogPrefix "!LogPrefix!" -SheetsInclude "!GenerateSheetsInclude!" -SheetsExclude "!GenerateSheetsExclude!" -SourcePath "!GenerateSourcePath!" -ClientName "!ClientName!"
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0bats\message.bat" "Finished %BATCH_NAME%"


exit /b %EXITCODE%
