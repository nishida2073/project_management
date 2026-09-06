@echo off
setlocal
cd /d "%~dp0"
node "..\..\md2png\build_pdf.js" "マニュアル.md" "マニュアル.pdf" --title-page --narrow-margins
endlocal
