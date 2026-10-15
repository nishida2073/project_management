@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "CommonDownloadPath=%BASE_PATH%download"
set "CommonConfigPath=%BASE_PATH%config"
set "CommonBaseTemplatePath=%BASE_PATH%template\base"
set "CommonCustomTemplatePath=%BASE_PATH%template\custom"
set "CommonCheckOutputPath=%BASE_PATH%checked"
set "CommonLogPath=%BASE_PATH%logs"
