@echo off


set "UseMacro=0"

set "MasterDataRootDir=%~dp0..\master"

set "ResultRootDir=%~dp0..\csv-results"

set "OutputRootDir=%~dp0..\output"

set "TemplateRootDir=%~dp0..\template"

set "OutputTestCollectDir=%OutputRootDir%\01_テスト集計結果"

set "OutputSurveyCollectDir=%OutputRootDir%\02_アンケート集計結果"

set "AutoHotkeyExePath=%~dp0..\AutoHotkey\v2\AutoHotkey.exe"
set "AutoHotkeyScriptPath=%~dp0..\AutoHotkey\scripts\download.ahk"
