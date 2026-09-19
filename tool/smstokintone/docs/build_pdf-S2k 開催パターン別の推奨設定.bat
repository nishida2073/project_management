@echo off
setlocal
cd /d "%~dp0"
set "NAME=%~n0"
set "NAME=%NAME:build_pdf-=%"
node "..\..\md2png\build_pdf.js" "%NAME%.md" "%NAME%.pdf" --title-page --narrow-margins --toc --anchor-levels=2,3,4 --toc-depth=4 --bookmark-depth=4 --page-numbers
endlocal
