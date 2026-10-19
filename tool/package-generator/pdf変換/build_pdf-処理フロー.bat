@echo off
setlocal
cd /d "%~dp0"
set "NAME=%~n0"
set "NAME=%NAME:build_pdf-=%"
node "..\..\md2png\build_pdf.js" "..\doc\02_ê›åv\%NAME%.md" "%NAME%.pdf" --title-page --narrow-margins --img-width=300 --toc --toc-depth=6 --bookmark-depth=6 --page-numbers --extra-css=%NAME%.css
endlocal
