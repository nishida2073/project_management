@echo off

for %%I in ("%~dp0..\..") do set "BASE_PATH=%%~fI\"

set "DownloadSiteUrl="
set "DownloadSitePath="
set "DownloadSiteTenantId="
set "DownloadLocalPath="

set "UploadSiteUrl="
set "UploadSitePath="
set "UploadSiteTenantId="
set "UploadLocalPath="
set "UploadItemsInclude="
set "UploadItemsExclude="

set "GenerateSourcePath=%BASE_PATH%download"
set "GenerateConfigPath=%BASE_PATH%clients\template\package_definition.xlsx"
set "GenerateWorkPath=%BASE_PATH%work"
set "GenerateOutputPath=%BASE_PATH%generated"
set "GenerateSheetsInclude="
set "GenerateSheetsExclude="
