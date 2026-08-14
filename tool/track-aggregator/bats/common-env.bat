@echo off

set "MasterDataRootDir=%~dp0..\master"

set "TemplateRootDir=%~dp0..\template"

set "ResultRootDir=%~dp0..\download"
set "TestResultRootDir=%ResultRootDir%\01_テスト"
set "SurveyResultRootDir=%ResultRootDir%\02_アンケート"

set "OutputRootDir=%~dp0..\output"
set "OutputTestCollectDir=%OutputRootDir%\集計結果"
set "OutputSurveyCollectDir=%OutputRootDir%\集計結果"
set "OutputCombineCollectDir=%OutputRootDir%\集計結果"
set "OutputYearComparisonCollectDir=%OutputRootDir%\集計結果"

set "PassScore=80"

set "AutoHotkeyExePath=%~dp0..\AutoHotkey\v2\AutoHotkey.exe"
set "AutoHotkeyScriptPath=%~dp0..\AutoHotkey\scripts\download.ahk"
set "TrackLoginUrl=https://nttdata-univ.train.tracks.run/auth/login"

for /f %%A in ('powershell -NoProfile -Command "(Get-Date).Year"') do set "TargetYear=%%A"

rem set "TargetYear=2025"
set "ComparePeriod=1"

set "CourseGroup1Name=ビジネス"
set "CourseGroup1Courses=ビジネス基礎,ビジネス応用"
set "CourseGroup2Name=IT技術基礎"
set "CourseGroup2Courses=社会を支えるITサービス,データベース技術入門,Web技術入門"
set "CourseGroup3Name=プログラミング"
set "CourseGroup3Courses=アルゴリズム入門,プログラミング基礎,プログラミング応用"
