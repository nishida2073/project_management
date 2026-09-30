@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

if not defined ClientDataRootDir set "ClientDataRootDir=%BASE_PATH%clients"

if not defined OutputRootDir set "OutputRootDir=%BASE_PATH%output"

if not defined TemplateRootDir set "TemplateRootDir=%BASE_PATH%template"

if not defined LOG_DIR set "LOG_DIR=%BASE_PATH%logs"

if not defined SourceType_Daily set "SourceType_Daily=業務日誌"
if not defined SourceType_Pulse set "SourceType_Pulse=パルスサーベイ"

if not defined TargetDateCodeField_Daily set "TargetDateCodeField_Daily=日付"
if not defined TargetUserCodeField_Daily set "TargetUserCodeField_Daily=個人ID"
if not defined TargetDateCodeField_Pulse set "TargetDateCodeField_Pulse=日付_0"
if not defined TargetUserCodeField_Pulse set "TargetUserCodeField_Pulse=個人ID"

if not defined OutputReportDir set "OutputReportDir=%OutputRootDir%\01_提出状況"
if not defined OutputCollectDataRootDir set "OutputCollectDataRootDir=%OutputRootDir%\02_アプリデータ集計"
if not defined OutputAlertRootDir set "OutputAlertRootDir=%OutputRootDir%\03_アラート検知結果"
if not defined OutputAlertBackupDir set "OutputAlertBackupDir=%OutputAlertRootDir%\backup"
