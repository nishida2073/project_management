@echo off

set "BASE_DIR=%~dp0"

if not defined COMMON_LOG_PATH set "COMMON_LOG_PATH=%BASE_DIR%log"

if not defined DOWNLOAD_SITE_URL set "DOWNLOAD_SITE_URL=https://nttdatajpprod.sharepoint.com/sites/SF476"
if not defined DOWNLOAD_FOLDER set "DOWNLOAD_FOLDER=Shared Documents/Fy27標準化Pj/テスト用/ツール/原本"
if not defined DOWNLOAD_LOCAL_DEST set "DOWNLOAD_LOCAL_DEST=%BASE_DIR%download"
if not defined DOWNLOAD_TENANT_ID set "DOWNLOAD_TENANT_ID=1fcf450d-bb71-4efd-ae5d-90c7be757e12"
if not defined DOWNLOAD_LOG_PREFIX set "DOWNLOAD_LOG_PREFIX=ダウンロード_"

if not defined GENERATE_SOURCE_BASE set "GENERATE_SOURCE_BASE=%DOWNLOAD_LOCAL_DEST%"
if not defined GENERATE_CONFIG_PATH set "GENERATE_CONFIG_PATH=%BASE_DIR%config\package_definition.xlsx"
if not defined GENERATE_SHEETS_INCLUDE set "GENERATE_SHEETS_INCLUDE="
if not defined GENERATE_SHEETS_EXCLUDE set "GENERATE_SHEETS_EXCLUDE="
if not defined GENERATE_WORK_PATH set "GENERATE_WORK_PATH=%BASE_DIR%work"
if not defined GENERATE_OUTPUT_PATH set "GENERATE_OUTPUT_PATH=%BASE_DIR%output"
if not defined GENERATE_LOG_PREFIX set "GENERATE_LOG_PREFIX=パッケージング_"

if not defined UPLOAD_SITE_URL set "UPLOAD_SITE_URL=%DOWNLOAD_SITE_URL%"
if not defined UPLOAD_FOLDER set "UPLOAD_FOLDER=Shared Documents/Fy27標準化Pj/テスト用/ツール/納品"
if not defined UPLOAD_LOCAL_SOURCE set "UPLOAD_LOCAL_SOURCE=%GENERATE_OUTPUT_PATH%"
if not defined UPLOAD_TENANT_ID set "UPLOAD_TENANT_ID=%DOWNLOAD_TENANT_ID%"
if not defined UPLOAD_LOG_PREFIX set "UPLOAD_LOG_PREFIX=アップロード_"
