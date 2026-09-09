@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "ClientDataRootDir=%BASE_PATH%clients"

set "OutputRootDir=%BASE_PATH%output"

set "TemplateRootDir=%BASE_PATH%template"

set "LOG_DIR=%BASE_PATH%logs"

set "SourceType_Daily=業務日誌"
set "SourceType_Pulse=パルスサーベイ"

set "TargetDateCodeField_Daily=日付"
set "TargetUserCodeField_Daily=個人ID"
set "TargetDateCodeField_Pulse=日付_0"
set "TargetUserCodeField_Pulse=個人ID"

set "OutputReportDir=%OutputRootDir%\01_提出状況"
set "OutputCollectDataRootDir=%OutputRootDir%\02_アプリデータ集計"
set "OutputAlertRootDir=%OutputRootDir%\03_アラート検知結果"
