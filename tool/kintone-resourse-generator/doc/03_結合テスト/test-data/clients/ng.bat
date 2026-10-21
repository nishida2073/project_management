@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "KintoneSubdomain=iiglepv0966f"
set "KintoneLoginName=user01"
set "KintonePassword=wrong-password"
set "KintoneBaseUrl=https://%KintoneSubdomain%.cybozu.com"
