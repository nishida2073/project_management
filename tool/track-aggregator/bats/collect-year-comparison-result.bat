@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

set "TargetGroupNameFilter="

for %%A in (%*) do (
    set "arg=%%~A"
    if "!arg:~0,1!"=="-" set "arg=!arg:~1!"
    for /f "tokens=1,* delims=:" %%K in ("!arg!") do (
        set "%%K=%%~L"
    )
)

if "!TargetGroupNameFilter!"=="" (
    set "TargetGroupNameFilter=*"
)

set "SCRIPT_PATH=%~dp0collect-year-comparison-result.ps1"

set "OutputTargetDir=%OutputYearComparisonCollectDir%"
set "TemplateFilePath=%TemplateRootDir%\経年比較結果.xlsx"

call "%~dp0message.bat" "Start Jobs %MyName% ALL"

for %%F in ("%ClientDataRootDir%\!TargetGroupNameFilter!.xlsx") do (
    set "GroupName=%%~nF"
    call "%~dp0message.bat" "Start %MyName% [!GroupName!]"
    set "envFile=%ClientDataRootDir%\!GroupName!.bat"
    if exist "!envFile!" (
        call "!envFile!"

        set "JOB_FLAG=%TEMP%\%MyName%!GroupName!_.running"
        set "ERROR_FLAG=%TEMP%\%MyName%!GroupName!_.failed"
        if exist "!ERROR_FLAG!" del /f /q "!ERROR_FLAG!"

        for /f "tokens=1 delims=-" %%X in ("!GroupName!") do set "TargetGroupName=%%X"
        for /f "tokens=2 delims=-" %%X in ("!GroupName!") do set "TargetYear=%%X"
        start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
          "try {" ^
          "  & '%SCRIPT_PATH%'" ^
          "     -ClientDataRootDir '!ClientDataRootDir!'" ^
          "     -TargetGroupName '!TargetGroupName!'" ^
          "     -TargetYear '!TargetYear!'" ^
          "     -ComparePeriod '!ComparePeriod!'" ^
          "     -OutputRootDir '!OutputTargetDir!'" ^
          "     -TemplateFilePath '!TemplateFilePath!'" ^
          "     -SurveyResultRootDir '!SurveyResultRootDir!'" ^
          "     -TestResultRootDir '!TestResultRootDir!'" ^
          "     -PassScore '!PassScore!'" ^
          "     -TargetCompanyNames '!TargetCompanyNames!'" ^
          "     -TargetRankNames '!TargetRankNames!'" ^
          "     -TargetClassNames '!TargetClassNames!'" ^
          "     -CourseGroupDefs '!CourseGroupDefs!'" ^
          "     -YearOrder '!YearOrder!'" ^
          "     -OutputFileSuffix '!OutputYearComparisonResultFileSuffix!'" ^
          "     -LogNamePrefix '%~n0'" ^
          "} catch {" ^
          "  New-Item -Path '!ERROR_FLAG!' -ItemType File -Force | Out-Null;" ^
          "  throw" ^
          "} finally {" ^
          "  Remove-Item -Path '!JOB_FLAG!' -Force" ^
          "}"

    ) else (
        call "%~dp0message.bat" "環境設定ファイルが見つかりません: !envFile!" "Red"
    )
    call "%~dp0message.bat" "Finished %MyName% [!GroupName!]"
)

call "%~dp0message.bat" "Waiting Jobs %MyName% ALL"

:WAIT_LOOP
set "ALL_DONE=1"
for %%F in ("%ClientDataRootDir%\!TargetGroupNameFilter!.xlsx") do (
    set "GroupName=%%~nF"
    set "GroupName=!GroupName:.xlsx=!"
    for /f "tokens=1 delims=-" %%X in ("!GroupName!") do set "GroupName=%%X"
    set "GroupName=!GroupName:.xlsx=!"
    set "JOB_FLAG=%TEMP%\%MyName%!GroupName!_.running"
    if exist "!JOB_FLAG!" set "ALL_DONE=0"
)
if !ALL_DONE! EQU 0 (
    timeout /t 1 >nul
    goto WAIT_LOOP
)

call "%~dp0message.bat" "Finished Jobs %MyName% ALL"

set "HAS_ERROR=0"
for %%F in ("%ClientDataRootDir%\!TargetGroupNameFilter!.xlsx") do (
    set "GroupName=%%~nF"
    set "GroupName=!GroupName:.xlsx=!"
    for /f "tokens=1 delims=-" %%X in ("!GroupName!") do set "GroupName=%%X"
    set "GroupName=!GroupName:.xlsx=!"
    set "ERROR_FLAG=%TEMP%\%MyName%!GroupName!_.failed"
    if exist "!ERROR_FLAG!" (
        set "HAS_ERROR=1"
        call "%~dp0message.bat" "Failed %MyName% [!GroupName!]" "Red"
        del /f /q "!ERROR_FLAG!"
    )
)
if !HAS_ERROR! EQU 1 exit /b 1