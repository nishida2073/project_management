@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "KintoneSubdomain=univ-kyousai-{x}"
set "KintoneLoginName="
set "KintonePassword="
set "KintoneBaseUrl=https://%KintoneSubdomain%.cybozu.com"
