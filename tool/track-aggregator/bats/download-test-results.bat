@echo off

call "%~dp0download-results.bat" %* -DownloadTarget:test -LogNamePrefix:%~n0

exit /b %ERRORLEVEL%
