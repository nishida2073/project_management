@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"
set "FILTER=%~1"
set "HAS_ERROR=0"

for /d %%D in ("..\..\doc\02_*") do (
    for %%F in ("%%~fD\*.md") do (
        set "RUN=1"
        if not "!FILTER!"=="" (
            set "RUN=0"
            if /i "%%~nF"=="!FILTER!" set "RUN=1"
        )
        if "!RUN!"=="1" (
            set "EXTRA="
            if exist "%%~nF.css" set "EXTRA=--extra-css=%%~nF.css"
            echo Building %%~nxF ...
            node "..\..\..\md2png\build_pdf.js" "%%~fF" "output\%%~nF.pdf" --title-page --narrow-margins --img-width=300 --toc --toc-depth=6 --bookmark-depth=6 --page-numbers !EXTRA!
            if errorlevel 1 (
                echo Failed: %%~nxF
                set "HAS_ERROR=1"
            )
        )
    )
)

endlocal & exit /b %HAS_ERROR%
