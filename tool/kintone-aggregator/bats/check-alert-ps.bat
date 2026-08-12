@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

if "%~1"=="" (
    for /f %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Date).AddDays(-1).ToString(\"yyyy-MM-dd\")"') do set "TargetDate=%%i"
) else (
    set "TargetDate=%~1"
)

set "SCRIPT_PATH=%~dp0check-alert-ps.ps1"

set "MasterDataRootDir=%MasterDataRootDir%"

set "CollectRootDir=%OutputCollectDataRootDir%\PS"
set "OutputTargetDir=%OutputAlertRootDir%\PS"
set "TemplateFilePath=%TemplateRootDir%\アラート検知-PS.xlsx"
set "ViewAllCourseSchedule=0"
set "ViewHolidayCourseSchedule=1"
set "AlertInterventionTerm=0"
set "AlertInterventionLimit=3"
set "UseRecovery=1"
set "RecoveryScriptPath=%~dp0recovery-check-alert.bat"

for %%F in ("%MasterDataRootDir%\*.xlsx") do (
    call "%~dp0message.bat" "Start %MyName% [%%~nF] {%TargetDate%}"
    
    set "envFile=%MasterDataRootDir%\%%~nF.bat"
    if exist "!envFile!" (
        call "!envFile!"
        
        set "JOB_FLAG=%TEMP%\%MyName%%%~nF_%TargetDate%.running"
        
        start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
          "& '%SCRIPT_PATH%'" ^
          "  -BaseUrl '!BaseUrl!'" ^
          "  -MasterDataFilePath '%%F'" ^
          "  -TargetGroupName '%%~nF'" ^
          "  -TemplateFilePath '%TemplateFilePath%'" ^
          "  -OutputRootDir '%OutputTargetDir%'" ^
          "  -CollectRootDir '%CollectRootDir%'" ^
          "  -TargetDate '%TargetDate%'" ^
          "  -ViewAllCourseSchedule '%ViewAllCourseSchedule%'" ^
          "  -ViewHolidayCourseSchedule '%ViewHolidayCourseSchedule%'" ^
          "  -AlertInterventionTerm '%AlertInterventionTerm%'" ^
          "  -AlertInterventionLimit '%AlertInterventionLimit%'" ^
          "  -UseRecovery '%UseRecovery%'" ^
          "  -RecoveryScriptPath '%RecoveryScriptPath%';" ^
          "Remove-Item -Path '!JOB_FLAG!' -Force;"
    ) else (
        call "%~dp0message.bat" "環境設定ファイルが見つかりません: !envFile!" "Red"
    )
    call "%~dp0message.bat" "Finished %MyName% [%%~nF] {%TargetDate%}"
)

call "%~dp0message.bat" "Start Jobs %MyName% ALL {%TargetDate%}"

:WAIT_LOOP
set "ALL_DONE=1"
for %%F in ("%MasterDataRootDir%\*.xlsx") do (
    set "JOB_FLAG=%TEMP%\%MyName%%%~nF_%TargetDate%.running"
    if exist "!JOB_FLAG!" set "ALL_DONE=0"
)
if !ALL_DONE! EQU 0 (
    timeout /t 1 >nul
    goto WAIT_LOOP
)

call "%~dp0message.bat" "Finished Jobs %MyName% ALL {%TargetDate%}"
