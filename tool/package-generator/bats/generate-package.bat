@echo off
setlocal enabledelayedexpansion

set "BATCH_NAME=%~nx0"

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
call "%~dp0..\clients\!ClientName!.bat"

call "%~dp0message.bat" "Start %BATCH_NAME%"


powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File "%~dp0generate-package.ps1" -ConfigPath "!GenerateConfigPath!" -WorkPath "!GenerateWorkPath!" -OutputPath "!GenerateOutputPath!" -LogPath "!CommonLogPath!" -LogNamePrefix "%~n0" -SheetsInclude "!GenerateSheetsInclude!" -SheetsExclude "!GenerateSheetsExclude!" -SourcePath "!GenerateSourcePath!" -ClientName "!ClientName!"
set "EXITCODE=%ERRORLEVEL%"

call "%~dp0message.bat" "Finished %BATCH_NAME%"


exit /b %EXITCODE%
