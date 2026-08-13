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

set "SourseDataDefs=サマリー_業務日誌@@1^|業務日誌提出状況,2,3,4,5,6,8^|^|date,9^|理解度;サマリー_パルスサーベイ@@1^|パルスサーベイ提出状況,9^|人間関係,10^|体調,11^|パルスサーベイフリーコメント"

set "CollectRootDir=%OutputCollectDataRootDir%"
set "CollectDataNotFoundMessage="

set "CheckedFileRootDir=%OutputReportDir%\%TargetDate%"

for %%F in ("%MasterDataRootDir%\%TargetGroupNameFilter%.xlsx") do (
    call "%~dp0message.bat" "Start %MyName% [%%~nF] {%TargetDate%}"
    
    set "JOB_FLAG=%TEMP%\%MyName%%%~nF_%TargetDate%.running"
    
    start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
      "& '%SCRIPT_PATH%'" ^
      "  -SourceRootDir '%CheckedFileRootDir%'" ^
      "  -TargetGroupName '%%~nF'" ^
      "  -TargetDate '%TargetDate%'" ^
      "  -SourseDataDefs '%SourseDataDefs%'" ^
      "  -CollectRootDir '%CollectRootDir%'" ^
      "  -CollectDataNotFoundMessage '%CollectDataNotFoundMessage%';" ^
      "Remove-Item -Path '!JOB_FLAG!' -Force;"
    
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
