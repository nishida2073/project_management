@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

if "%~1"=="" (
    for /f %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Date).AddDays(-1).ToString(\"yyyy-MM-dd\")"') do set "TargetDate=%%i"
) else (
    set "TargetDate=%~1"
)
if "%~2"=="" (
    set "TargetGroupNameFilter=*"
) else (
    set "TargetGroupNameFilter=%~2"
)

set "SCRIPT_PATH=%~dp0collect-app-data.ps1"
set "MasterDataRootDir=%MasterDataRootDir%"

set "SourseDataDefsPath=%~dp0collect-data-defs.txt"

set "CollectRootDir=%OutputCollectDataRootDir%"
set "CollectDataNotFoundMessage="

set "CheckedFileRootDir=%OutputReportDir%\%TargetDate%"

for %%F in ("%MasterDataRootDir%\%TargetGroupNameFilter%.xlsx") do (
    call "%~dp0message.bat" "Start %MyName% [%%~nF] {%TargetDate%}"

    set "JOB_FLAG=%TEMP%\%MyName%%%~nF_%TargetDate%.running"
    set "ERROR_FLAG=%TEMP%\%MyName%%%~nF_%TargetDate%.failed"
    if exist "!ERROR_FLAG!" del /f /q "!ERROR_FLAG!"

    start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
      "try {" ^
      "  & '%SCRIPT_PATH%'" ^
      "     -SourceRootDir '%CheckedFileRootDir%'" ^
      "     -TargetGroupName '%%~nF'" ^
      "     -TargetDate '%TargetDate%'" ^
      "     -SourseDataDefsPath '%SourseDataDefsPath%'" ^
      "     -CollectRootDir '%CollectRootDir%'" ^
      "     -CollectDataNotFoundMessage '%CollectDataNotFoundMessage%'" ^
      "} catch {" ^
      "  New-Item -Path '!ERROR_FLAG!' -ItemType File -Force | Out-Null;" ^
      "  throw" ^
      "} finally {" ^
      "  Remove-Item -Path '!JOB_FLAG!' -Force" ^
      "}"

    call "%~dp0message.bat" "Finished %MyName% [%%~nF] {%TargetDate%}"
)

call "%~dp0message.bat" "Start Jobs %MyName% ALL {%TargetDate%}"

:WAIT_LOOP
set "ALL_DONE=1"
for %%F in ("%MasterDataRootDir%\%TargetGroupNameFilter%.xlsx") do (
    set "JOB_FLAG=%TEMP%\%MyName%%%~nF_%TargetDate%.running"
    if exist "!JOB_FLAG!" set "ALL_DONE=0"
)
if !ALL_DONE! EQU 0 (
    timeout /t 1 >nul
    goto WAIT_LOOP
)

call "%~dp0message.bat" "Finished Jobs %MyName% ALL {%TargetDate%}"

set "HAS_ERROR=0"
for %%F in ("%MasterDataRootDir%\%TargetGroupNameFilter%.xlsx") do (
    set "ERROR_FLAG=%TEMP%\%MyName%%%~nF_%TargetDate%.failed"
    if exist "!ERROR_FLAG!" (
        set "HAS_ERROR=1"
        call "%~dp0message.bat" "Failed %MyName% [%%~nF] {%TargetDate%}" "Red"
        del /f /q "!ERROR_FLAG!"
    )
)
if !HAS_ERROR! EQU 1 exit /b 1