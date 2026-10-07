@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "KINTONE_SUB_DOMAIN="
set "KINTONE_LOGIN="
set "KINTONE_PASSWORD="
set "KINTONE_BASE_URL=https://%KINTONE_SUB_DOMAIN%.cybozu.com"
