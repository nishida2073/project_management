@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

if not defined COMMON_LOG_PATH set "COMMON_LOG_PATH=%BASE_PATH%logs"

if not defined DOWNLOAD_ENABLED set "DOWNLOAD_ENABLED=1"
if not defined DOWNLOAD_SITE_URL set "DOWNLOAD_SITE_URL=https://nttdatajpprod.sharepoint.com/sites/SF476"
if not defined DOWNLOAD_SITE_PATH set "DOWNLOAD_SITE_PATH=Shared Documents/Fy27�W����Pj/�e�X�g�p/�c�[��/���{"
if not defined DOWNLOAD_SITE_TENANT_ID set "DOWNLOAD_SITE_TENANT_ID=1fcf450d-bb71-4efd-ae5d-90c7be757e12"
if not defined DOWNLOAD_LOCAL_PATH set "DOWNLOAD_LOCAL_PATH=%BASE_PATH%download"
if not defined DOWNLOAD_LOG_PREFIX set "DOWNLOAD_LOG_PREFIX=�_�E�����[�h_"

if not defined GENERATE_ENABLED set "GENERATE_ENABLED=1"
if not defined GENERATE_SOURCE_PATH set "GENERATE_SOURCE_PATH=%DOWNLOAD_LOCAL_PATH%"
if not defined GENERATE_CONFIG_PATH set "GENERATE_CONFIG_PATH=%DOWNLOAD_LOCAL_PATH%/package_definition.xlsx"
if not defined GENERATE_SHEETS_INCLUDE set "GENERATE_SHEETS_INCLUDE="
if not defined GENERATE_SHEETS_EXCLUDE set "GENERATE_SHEETS_EXCLUDE=�e���v���[�g"
if not defined GENERATE_WORK_PATH set "GENERATE_WORK_PATH=%BASE_PATH%work"
if not defined GENERATE_OUTPUT_PATH set "GENERATE_OUTPUT_PATH=%BASE_PATH%generated"
if not defined GENERATE_LOG_PREFIX set "GENERATE_LOG_PREFIX=�p�b�P�[�W�쐬_"

if not defined UPLOAD_ENABLED set "UPLOAD_ENABLED=0"
if not defined UPLOAD_SITE_URL set "UPLOAD_SITE_URL=%DOWNLOAD_SITE_URL%"
if not defined UPLOAD_SITE_PATH set "UPLOAD_SITE_PATH=Shared Documents/Fy27�W����Pj/�e�X�g�p/�c�[��/�[�i"
if not defined UPLOAD_SITE_TENANT_ID set "UPLOAD_SITE_TENANT_ID=%DOWNLOAD_SITE_TENANT_ID%"
if not defined UPLOAD_LOCAL_PATH set "UPLOAD_LOCAL_PATH=%GENERATE_OUTPUT_PATH%"
if not defined UPLOAD_ITEMS_INCLUDE set "UPLOAD_ITEMS_INCLUDE=*.zip"
if not defined UPLOAD_ITEMS_EXCLUDE set "UPLOAD_ITEMS_EXCLUDE="
if not defined UPLOAD_LOG_PREFIX set "UPLOAD_LOG_PREFIX=�A�b�v���[�h_"
