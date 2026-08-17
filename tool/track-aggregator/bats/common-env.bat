@echo off

set "MasterDataRootDir=%~dp0..\master"

set "TemplateRootDir=%~dp0..\template"

set "ResultRootDir=%~dp0..\tmp\実施結果"
set "TestResultRootDir=%ResultRootDir%\01_テスト"
set "SurveyResultRootDir=%ResultRootDir%\02_アンケート"

set "OutputRootDir=%~dp0..\tmp\集計結果"
set "OutputTestCollectDir=%OutputRootDir%\テスト"
set "OutputTestResultFileSuffix=テスト結果"
set "OutputSurveyCollectDir=%OutputRootDir%\アンケート"
set "OutputSurveyResultFileSuffix=アンケート結果"
set "OutputCombineCollectDir=%OutputRootDir%\統合"
set "OutputCombineResultFileSuffix=統合結果"
set "OutputYearComparisonCollectDir=%OutputRootDir%\経年比較"
set "OutputYearComparisonResultFileSuffix=経年比較結果"

set "PassScore=80"

set "AutoHotkeyExePath=%~dp0..\AutoHotkey\v2\AutoHotkey.exe"
set "AutoHotkeyScriptPath=%~dp0..\AutoHotkey\scripts\download.ahk"
set "TrackLoginUrl=https://nttdata-univ.train.tracks.run/auth/login"

for /f %%A in ('powershell -NoProfile -Command "(Get-Date).Year"') do set "TargetYear=%%A"

rem set "TargetYear=2025"
set "ComparePeriod=1"

rem 出力対象の絞り込み（カンマ区切り、複数指定可）。空の場合はすべてを対象とする
set "TargetCompanyNames="
set "TargetRankNames="
set "TargetClassNames="

rem コースグループ定義。「グループ名:コース1,コース2」を ; で連結する形式
set "CourseGroupDefs=ビジネス:ビジネス基礎,ビジネス応用;IT技術基礎:社会を支えるITサービス,データベース技術入門,Web技術入門;プログラミング:アルゴリズム入門,プログラミング基礎,プログラミング応用"

rem 経年比較シートの年度行の表示順。0:昇順（古い→新しい） 1:降順（新しい→古い、既定）
set "YearOrder=1"
