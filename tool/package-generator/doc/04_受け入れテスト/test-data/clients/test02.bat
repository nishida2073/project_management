@echo off

set "GenerateSourcePath=%BASE_PATH%download"
set "GenerateConfigPath=%BASE_PATH%clients\test02.xlsx"
set "GenerateWorkPath=%BASE_PATH%work"
set "GenerateOutputPath=%BASE_PATH%generated"
set "GenerateSheetsInclude="
set "GenerateSheetsExclude="

set "KintoneSubdomain="
set "KintoneLoginName="
set "KintonePassword="
set "KintoneBaseUrl=https://%KintoneSubdomain%.cybozu.com"
set "TargetAppId="