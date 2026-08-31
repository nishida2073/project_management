@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "ClientDataRootDir=%BASE_PATH%clients"

set "OutputRootDir=%BASE_PATH%output"

set "TemplateRootDir=%BASE_PATH%template"

set "LOG_DIR=%BASE_PATH%logs"


set "OutputReportDir=%OutputRootDir%\01_提出状況"
set "OutputCollectDataRootDir=%OutputRootDir%\02_アプリデータ集計"
set "OutputAlertRootDir=%OutputRootDir%\03_アラート検知結果"
