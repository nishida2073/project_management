@echo off
setlocal
cd /d "%~dp0"
set "NAME=%~n0"
set "NAME=%NAME:build_pdf-=%"
node "..\..\md2png\build_pdf.js" "%NAME%.md" "%NAME%.pdf" --title-page --narrow-margins
endlocal
