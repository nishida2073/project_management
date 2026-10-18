@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "ClientDataRootDir=%BASE_PATH%clients"

set "OutputRootDir=%BASE_PATH%output"

set "TemplateRootDir=%BASE_PATH%template"

set "CommonLogPath=%BASE_PATH%logs"

set "SourceTypeDaily=業務日誌"
set "SourceTypePulse=パルスサーベイ"

set "TargetDateCodeFieldDaily=日付"
set "TargetUserCodeFieldDaily=個人ID"
set "TargetDateCodeFieldPulse=日付_0"
set "TargetUserCodeFieldPulse=個人ID"

set "OutputReportDir=%OutputRootDir%\01_提出状況"
set "OutputCollectDataRootDir=%OutputRootDir%\02_アプリデータ集計"
set "OutputAlertRootDir=%OutputRootDir%\03_アラート検知結果"
set "OutputAlertBackupDir=%OutputAlertRootDir%\backup"
