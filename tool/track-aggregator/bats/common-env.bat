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