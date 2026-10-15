@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "COMMON_DOWNLOAD_PATH=%BASE_PATH%download"
set "COMMON_CONFIG_PATH=%BASE_PATH%config"
set "COMMON_BASE_TEMPLATE_PATH=%BASE_PATH%template\base"
set "COMMON_CUSTOM_TEMPLATE_PATH=%BASE_PATH%template\custom"
set "COMMON_CHECK_OUTPUT_PATH=%BASE_PATH%checked"
set "COMMON_LOG_PATH=%BASE_PATH%logs"
