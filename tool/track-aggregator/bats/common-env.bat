@echo off

set "MasterDataRootDir=%~dp0..\master"

set "ResultRootDir=%~dp0..\download"

set "OutputRootDir=%~dp0..\output"

set "TemplateRootDir=%~dp0..\template"

set "OutputTestCollectDir=%OutputRootDir%\集計結果"

set "OutputSurveyCollectDir=%OutputRootDir%\集計結果"

set "OutputCombineCollectDir=%OutputRootDir%\集計結果"

set "AutoHotkeyExePath=%~dp0..\AutoHotkey\v2\AutoHotkey.exe"
set "AutoHotkeyScriptPath=%~dp0..\AutoHotkey\scripts\download.ahk"
set "TrackLoginUrl=https://nttdata-univ.train.tracks.run/auth/login"
