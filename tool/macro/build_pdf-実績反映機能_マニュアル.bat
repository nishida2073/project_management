@echo off
setlocal
cd /d "%~dp0"
set "NAME=%~n0"
set "NAME=%NAME:build_pdf-=%"
node "..\md2png\build_pdf.js" "%NAME%.md" "%NAME%.pdf" --title-page --narrow-margins --toc -toc-depth=5 --bookmark-depth=5 --page-numbers --extra-css="%NAME%.css"
endlocal
