@echo off

set "BASE_DIR=%~dp0"

if not defined COMMON_WORK_PATH set "COMMON_WORK_PATH=%BASE_DIR%work"
if not defined COMMON_OUTPUT_PATH set "COMMON_OUTPUT_PATH=%BASE_DIR%output"
if not defined COMMON_LOG_PATH set "COMMON_LOG_PATH=%BASE_DIR%log"

if not defined SYNC_SITE_URL set "SYNC_SITE_URL=https://nttdatajpprod.sharepoint.com/sites/SF476"
if not defined SYNC_FOLDER set "SYNC_FOLDER=Shared Documents/Fy27標準化Pj/テスト用/sharepoint用"
if not defined SYNC_LOCAL_DEST set "SYNC_LOCAL_DEST=%BASE_DIR%sync"
if not defined SYNC_TENANT_ID set "SYNC_TENANT_ID=1fcf450d-bb71-4efd-ae5d-90c7be757e12"
if not defined SYNC_LOG_PREFIX set "SYNC_LOG_PREFIX=ファイル同期_"

if not defined GENERATE_SOURCE_BASE set "GENERATE_SOURCE_BASE=%SYNC_LOCAL_DEST%"
if not defined GENERATE_CONFIG_PATH set "GENERATE_CONFIG_PATH=%BASE_DIR%config\package_definition.xlsx"
if not defined GENERATE_SHEETS_INCLUDE set "GENERATE_SHEETS_INCLUDE="
if not defined GENERATE_SHEETS_EXCLUDE set "GENERATE_SHEETS_EXCLUDE="
if not defined GENERATE_LOG_PREFIX set "GENERATE_LOG_PREFIX=パッケージング_"
