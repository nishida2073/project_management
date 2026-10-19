@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\capture\capture-screenshots.ps1" -Root "%~dp0..\.." -OutDir "%~dp0screenshots" -PlanFile "%~dp0capture-plan.txt"
exit /b %ERRORLEVEL%
