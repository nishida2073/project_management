@echo off

call "%~dp0download-results.bat" %* -DownloadTarget:survey -LogNamePrefix:%~n0

exit /b %ERRORLEVEL%
