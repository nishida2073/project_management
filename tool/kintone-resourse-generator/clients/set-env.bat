@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

if not defined COMMON_DOWNLOAD_PATH set "COMMON_DOWNLOAD_PATH=%BASE_PATH%download"
if not defined COMMON_CONFIG_PATH set "COMMON_CONFIG_PATH=%BASE_PATH%config"
if not defined COMMON_TEMPLATE_PATH set "COMMON_TEMPLATE_PATH=%BASE_PATH%template"
if not defined COMMON_CHECK_OUTPUT_PATH set "COMMON_CHECK_OUTPUT_PATH=%BASE_PATH%checked"
if not defined COMMON_LOG_PATH set "COMMON_LOG_PATH=%BASE_PATH%logs"

if exist "%~dp0set-kintone.bat" call "%~dp0set-kintone.bat"
