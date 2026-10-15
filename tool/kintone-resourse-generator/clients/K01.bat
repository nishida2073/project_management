@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "KintoneSubdomain=iiglepv0966f"
set "KintoneLoginName=user01"
set "KintonePassword=abcd1234"
set "BaseUrl=https://%KintoneSubdomain%.cybozu.com"
