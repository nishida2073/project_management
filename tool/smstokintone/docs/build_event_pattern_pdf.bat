@echo off
setlocal
cd /d "%~dp0"
node "..\..\md2png\build_pdf.js" "開催パターン別設定.md" "開催パターン別設定.pdf"
endlocal
