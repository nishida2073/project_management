@echo off
setlocal
set "NODE_PATH=c:\myrepo\project_management\tools\md2png\node_modules"
cd /d "%~dp0"
node build_manual_pdf.js
endlocal
