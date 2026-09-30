@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "COMMON_DOWNLOAD_PATH=%BASE_PATH%download"
set "COMMON_CONFIG_PATH=%BASE_PATH%config"
set "COMMON_BASE_TEMPLATE_PATH=%BASE_PATH%template\base"
set "COMMON_CUSTOM_TEMPLATE_PATH=%BASE_PATH%template\custom"
set "COMMON_CHECK_OUTPUT_PATH=%BASE_PATH%checked"
set "COMMON_LOG_PATH=%BASE_PATH%logs"

set "KINTONE_SUB_DOMAIN=iiglepv0966f"
set "KINTONE_LOGIN=user01"
set "KINTONE_PASSWORD=abcd1234"
set "KINTONE_BASE_URL=https://%KINTONE_SUB_DOMAIN%.cybozu.com"
