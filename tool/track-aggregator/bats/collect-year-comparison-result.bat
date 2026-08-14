@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

set "SCRIPT_PATH=%~dp0collect-year-comparison-result.ps1"

set "OutputTargetDir=%OutputYearComparisonCollectDir%"
set "TemplateFilePath=%TemplateRootDir%\年度比較結果.xlsx"

for /f "delims=" %%F in ('powershell -NoProfile -Command "& '%~dp0select-current-master-files.ps1' -MasterDataRootDir '%MasterDataRootDir%' -TargetYear %TargetYear% -ComparePeriod %ComparePeriod%"') do (
    call "%~dp0message.bat" "Start %MyName% [%%~nF]"

    call "%~dp0resolve-env-file.bat" "%%~nF"
    if exist "!envFile!" (
        call "!envFile!"

        set "JOB_FLAG=%TEMP%\%MyName%%%~nF_.running"

        start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
          "& '%SCRIPT_PATH%'" ^
          "   -MasterDataFilePath '%%F'" ^
          "   -TargetGroupName '%%~nF'" ^
          "   -TargetYear '%TargetYear%'" ^
          "   -ComparePeriod '%ComparePeriod%'" ^
          "   -OutputRootDir '%OutputTargetDir%'" ^
          "   -TemplateFilePath '!TemplateFilePath!'" ^
          "   -SurveyResultRootDir '%SurveyResultRootDir%'" ^
          "   -TestResultRootDir '%TestResultRootDir%'" ^
          "   -PassScore '%PassScore%';" ^
          "Remove-Item -Path '!JOB_FLAG!' -Force;"

    ) else (
        call "%~dp0message.bat" "環境設定ファイルが見つかりません: !envFile!" "Red"
    )
    call "%~dp0message.bat" "Finished %MyName% [%%~nF]"
)

call "%~dp0message.bat" "Start Jobs %MyName% ALL"

:WAIT_LOOP
set "ALL_DONE=1"
for /f "delims=" %%F in ('powershell -NoProfile -Command "& '%~dp0select-current-master-files.ps1' -MasterDataRootDir '%MasterDataRootDir%' -TargetYear %TargetYear% -ComparePeriod %ComparePeriod%"') do (
    set "JOB_FLAG=%TEMP%\%MyName%%%~nF_%TargetDate%.running"
    if exist "!JOB_FLAG!" set "ALL_DONE=0"
)
if !ALL_DONE! EQU 0 (
    timeout /t 1 >nul
    goto WAIT_LOOP
)

call "%~dp0message.bat" "Finished Jobs %MyName% ALL"