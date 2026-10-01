@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

set "CommonLogPath=%BASE_PATH%logs"
