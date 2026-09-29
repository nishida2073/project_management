@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

if not defined COMMON_DOWNLOAD_PATH set "COMMON_DOWNLOAD_PATH=%BASE_PATH%download"
if not defined COMMON_CONFIG_PATH set "COMMON_CONFIG_PATH=%BASE_PATH%config"
if not defined COMMON_BASE_TEMPLATE_PATH set "COMMON_BASE_TEMPLATE_PATH=%BASE_PATH%template\base"
if not defined COMMON_CUSTOM_TEMPLATE_PATH set "COMMON_CUSTOM_TEMPLATE_PATH=%BASE_PATH%template\custom"
if not defined COMMON_CHECK_OUTPUT_PATH set "COMMON_CHECK_OUTPUT_PATH=%BASE_PATH%checked"
if not defined COMMON_LOG_PATH set "COMMON_LOG_PATH=%BASE_PATH%logs"

if not defined KINTONE_BASE_URL set "KINTONE_BASE_URL=https://iiglepv0966f.cybozu.com"
if not defined KINTONE_LOGIN set "KINTONE_LOGIN=user01"
if not defined KINTONE_PASSWORD set "KINTONE_PASSWORD=abcd1234"
