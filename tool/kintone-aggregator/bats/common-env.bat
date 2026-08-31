@echo off


set "ClientDataRootDir=%~dp0..\clients"

set "OutputRootDir=%~dp0..\output"

set "TemplateRootDir=%~dp0..\template"

set "LOG_DIR=%~dp0..\logs"


set "OutputReportDir=%OutputRootDir%\01_提出状況"
set "OutputCollectDataRootDir=%OutputRootDir%\02_アプリデータ集計"
set "OutputAlertRootDir=%OutputRootDir%\03_アラート検知結果"


