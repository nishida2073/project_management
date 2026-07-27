@echo off
setlocal

if "%~1"=="" (
  echo Usage: md2pdf.bat "input.md"
  echo   or drag-and-drop a .md file onto this batch file.
  pause
  exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set "OUT=%~dpn1.pdf"

echo Rendering "%~1" to "%OUT%" ...
node "%SCRIPT_DIR%tools\md2png\render-pdf.js" "%~1" "%OUT%"

if errorlevel 1 (
  echo Failed.
  pause
  exit /b 1
)

echo Done: %OUT%
pause
