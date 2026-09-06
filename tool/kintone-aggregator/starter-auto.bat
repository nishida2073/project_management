@echo off
chcp 932 >nul

set "BATCH=all.bat"
call "%~dp0%BATCH%"
