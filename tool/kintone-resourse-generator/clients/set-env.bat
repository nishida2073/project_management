@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

if not defined KINTONE_BASE_URL set "KINTONE_BASE_URL=https://bm5z6rewq6pg.cybozu.com"
if not defined KINTONE_DOWNLOAD_PATH set "KINTONE_DOWNLOAD_PATH=%BASE_PATH%download"
if not defined KINTONE_CONFIG_PATH set "KINTONE_CONFIG_PATH=%BASE_PATH%config"
if not defined KINTONE_TEMPLATE_PATH set "KINTONE_TEMPLATE_PATH=%BASE_PATH%template"
if not defined KINTONE_CHECK_OUTPUT_PATH set "KINTONE_CHECK_OUTPUT_PATH=%BASE_PATH%checked"
if not defined KINTONE_LOG_PATH set "KINTONE_LOG_PATH=%BASE_PATH%log"

if exist "%~dp0set-credentials.bat" call "%~dp0set-credentials.bat"
