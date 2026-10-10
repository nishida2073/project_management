@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "KINTONE_SUB_DOMAIN=iiglepv0966f"
set "KINTONE_LOGIN=user01"
set "KINTONE_PASSWORD=abcd1234"
set "KINTONE_BASE_URL=https://%KINTONE_SUB_DOMAIN%.cybozu.com"
