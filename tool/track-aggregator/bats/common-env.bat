@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

if not defined ClientDataRootDir set "ClientDataRootDir=%BASE_PATH%clients"

if not defined TemplateRootDir set "TemplateRootDir=%BASE_PATH%template"

if not defined LOG_DIR set "LOG_DIR=%BASE_PATH%logs"

if not defined ResultRootDir set "ResultRootDir=%BASE_PATH%output\実施結果"
if not defined TestResultRootDir set "TestResultRootDir=%ResultRootDir%\01_テスト"
if not defined SurveyResultRootDir set "SurveyResultRootDir=%ResultRootDir%\02_アンケート"

if not defined OutputRootDir set "OutputRootDir=%BASE_PATH%output\集計結果"
if not defined OutputTestCollectDir set "OutputTestCollectDir=%OutputRootDir%\テスト"
if not defined OutputTestResultFileSuffix set "OutputTestResultFileSuffix=テスト結果"
if not defined OutputSurveyCollectDir set "OutputSurveyCollectDir=%OutputRootDir%\アンケート"
if not defined OutputSurveyResultFileSuffix set "OutputSurveyResultFileSuffix=アンケート結果"
if not defined OutputCombineCollectDir set "OutputCombineCollectDir=%OutputRootDir%\統合"
if not defined OutputCombineResultFileSuffix set "OutputCombineResultFileSuffix=統合結果"
if not defined OutputYearComparisonCollectDir set "OutputYearComparisonCollectDir=%OutputRootDir%\経年比較"
if not defined OutputYearComparisonResultFileSuffix set "OutputYearComparisonResultFileSuffix=経年比較結果"

if not defined PassScore set "PassScore=80"

if not defined AutoHotkeyExePath set "AutoHotkeyExePath=%BASE_PATH%AutoHotkey\v2\AutoHotkey.exe"
if not defined AutoHotkeyScriptPath set "AutoHotkeyScriptPath=%BASE_PATH%AutoHotkey\scripts\download.ahk"
if not defined TrackLoginUrl set "TrackLoginUrl=https://nttdata-univ.train.tracks.run/auth/login"

for /f %%A in ('powershell -NoProfile -Command "(Get-Date).Year"') do set "TargetYear=%%A"

rem set "TargetYear=2025"
if not defined ComparePeriod set "ComparePeriod=1"

rem 出力対象の絞り込み（カンマ区切り、複数指定可）。空の場合はすべてを対象とする
if not defined TargetCompanyNames set "TargetCompanyNames="
if not defined TargetRankNames set "TargetRankNames="
if not defined TargetClassNames set "TargetClassNames="

rem コースグループ定義。「グループ名:コース1,コース2」を ; で連結する形式
if not defined CourseGroupDefs set "CourseGroupDefs=ビジネス:ビジネス基礎,ビジネス応用;IT技術基礎:社会を支えるITサービス,データベース技術入門,Web技術入門;プログラミング:アルゴリズム入門,プログラミング基礎,プログラミング応用"

rem 経年比較シートの年度行の表示順。0:昇順（古い→新しい） 1:降順（新しい→古い、既定）
if not defined YearOrder set "YearOrder=1"
