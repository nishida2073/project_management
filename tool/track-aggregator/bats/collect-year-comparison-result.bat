@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

rem コマンドラインから名前指定で会社名・ランク・クラスを絞り込む場合（未指定の項目はcommon-env.batの既定値＝空(全体)のまま）
rem 区切りは = ではなく : を使うこと（cmd.exeは = とカンマを引数の区切り文字として扱うため）。先頭の - は付けても付けなくても可
rem 1社・1ランク・1クラスだけ指定するならクォート不要。複数値をカンマ区切りで指定する場合は引数ごとに "" で囲むこと
rem 例: collect-year-comparison-result.bat TargetCompanyNames:会社A "TargetRankNames:S,A"
for %%A in (%*) do (
    set "arg=%%~A"
    if "!arg:~0,1!"=="-" set "arg=!arg:~1!"
    for /f "tokens=1,* delims=:" %%K in ("!arg!") do (
        if /i "%%K"=="TargetCompanyNames" set "TargetCompanyNames=%%~L"
        if /i "%%K"=="TargetRankNames" set "TargetRankNames=%%~L"
        if /i "%%K"=="TargetClassNames" set "TargetClassNames=%%~L"
    )
)

set "SCRIPT_PATH=%~dp0collect-year-comparison-result.ps1"

set "OutputTargetDir=%OutputYearComparisonCollectDir%"
set "TemplateFilePath=%TemplateRootDir%\年度比較結果.xlsx"

for /f "delims=" %%G in ('powershell -NoProfile -Command "& '%~dp0select-current-master-files.ps1' -MasterDataRootDir '%MasterDataRootDir%' -TargetYear %TargetYear% -ComparePeriod %ComparePeriod%"') do (
    call "%~dp0message.bat" "Start %MyName% [%%G]"

    call "%~dp0resolve-env-file.bat" "%%G"
    if exist "!envFile!" (
        call "!envFile!"

        set "JOB_FLAG=%TEMP%\%MyName%%%G_.running"

        start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
          "& '%SCRIPT_PATH%'" ^
          "   -MasterDataRootDir '%MasterDataRootDir%'" ^
          "   -TargetGroupName '%%G'" ^
          "   -TargetYear '%TargetYear%'" ^
          "   -ComparePeriod '%ComparePeriod%'" ^
          "   -OutputRootDir '%OutputTargetDir%'" ^
          "   -TemplateFilePath '!TemplateFilePath!'" ^
          "   -SurveyResultRootDir '%SurveyResultRootDir%'" ^
          "   -TestResultRootDir '%TestResultRootDir%'" ^
          "   -PassScore '%PassScore%'" ^
          "   -TargetCompanyNames '%TargetCompanyNames%'" ^
          "   -TargetRankNames '%TargetRankNames%'" ^
          "   -TargetClassNames '%TargetClassNames%';" ^
          "Remove-Item -Path '!JOB_FLAG!' -Force;"

    ) else (
        call "%~dp0message.bat" "環境設定ファイルが見つかりません: !envFile!" "Red"
    )
    call "%~dp0message.bat" "Finished %MyName% [%%G]"
)

call "%~dp0message.bat" "Start Jobs %MyName% ALL"

:WAIT_LOOP
set "ALL_DONE=1"
for /f "delims=" %%G in ('powershell -NoProfile -Command "& '%~dp0select-current-master-files.ps1' -MasterDataRootDir '%MasterDataRootDir%' -TargetYear %TargetYear% -ComparePeriod %ComparePeriod%"') do (
    set "JOB_FLAG=%TEMP%\%MyName%%%G_.running"
    if exist "!JOB_FLAG!" set "ALL_DONE=0"
)
if !ALL_DONE! EQU 0 (
    timeout /t 1 >nul
    goto WAIT_LOOP
)

call "%~dp0message.bat" "Finished Jobs %MyName% ALL"