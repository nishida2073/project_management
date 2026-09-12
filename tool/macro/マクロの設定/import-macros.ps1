param(
    [string]$XlsmPath,
    [string]$MacroDir,
    [string]$BackupDir
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $MacroDir) {
    $MacroDir = Join-Path $scriptDir '..\macros'
}
$MacroDir = (Resolve-Path -Path $MacroDir).ProviderPath

if (-not $XlsmPath) {
    $xlsmFiles = Get-ChildItem -Path $scriptDir\.. -Filter '*.xlsm' | Where-Object { $_.Name -notlike '~$*' }
    if ($xlsmFiles.Count -ne 1) {
        Write-Host "ERROR: could not auto-detect a single .xlsm file in $scriptDir\.. (found $($xlsmFiles.Count)). Pass -XlsmPath explicitly."
        exit 1
    }
    $XlsmPath = $xlsmFiles[0].FullName
}
$XlsmPath = (Resolve-Path -Path $XlsmPath).ProviderPath

if (-not $BackupDir) {
    $BackupDir = Join-Path $scriptDir 'backup'
}
if (-not (Test-Path -Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

$xlsmFile = Get-Item -Path $XlsmPath
$xlsmBaseName = $xlsmFile.BaseName

$thisWorkbookFile = Get-ChildItem -Path $MacroDir -Filter "${xlsmBaseName}_ThisWorkbook.bas" | Select-Object -First 1
if (-not $thisWorkbookFile) {
    Write-Host "ERROR: no '${xlsmBaseName}_ThisWorkbook.bas' in $MacroDir"
    exit 1
}

$moduleFile = Get-ChildItem -Path $MacroDir -Filter "${xlsmBaseName}_*.bas" | Where-Object { $_.FullName -ne $thisWorkbookFile.FullName } | Select-Object -First 1
if (-not $moduleFile) {
    Write-Host "ERROR: no '${xlsmBaseName}_<ModuleName>.bas' in $MacroDir"
    exit 1
}

$moduleName = $moduleFile.BaseName.Substring($xlsmBaseName.Length + 1)

Write-Host "Target workbook  : $($xlsmFile.FullName)"
Write-Host "Module source    : $($moduleFile.FullName)  ->  module name: $moduleName"
Write-Host "ThisWorkbook src : $($thisWorkbookFile.FullName)"

$backupName = "{0}_{1}{2}" -f `
    $xlsmFile.BaseName, `
    (Get-Date -Format 'yyyyMMdd-HHmmss'), `
    $xlsmFile.Extension
$backupPath = Join-Path $BackupDir $backupName
Copy-Item -Path $xlsmFile.FullName -Destination $backupPath
Write-Host "Backup created   : $backupPath"

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$excel.EnableEvents = $false

$wb = $null
try {
    $wb = $excel.Workbooks.Open($xlsmFile.FullName)

    $appendFile = Get-ChildItem -Path $MacroDir -Filter "${xlsmBaseName}_Append.xlsx" | Select-Object -First 1
    if ($appendFile) {
        try {
            $wbAdd = $excel.Workbooks.Open($appendFile.FullName, 0, $true)
            try {
                foreach ($srcSheet in @($wbAdd.Sheets)) {
                    $exists = $false
                    foreach ($existingSheet in @($wb.Sheets)) {
                        if ($existingSheet.Name -eq $srcSheet.Name) { $exists = $true; break }
                    }
                    if (-not $exists) {
                        $srcSheet.Copy([Type]::Missing, $wb.Sheets.Item($wb.Sheets.Count))
                        $newSheet = $wb.Sheets.Item($srcSheet.Name)
                        $newSheet.Visible = 0
                        if ($newSheet.Visible -ne 0) {
                            Write-Host "WARN: could not hide sheet '$($srcSheet.Name)' (Visible=$($newSheet.Visible))"
                        }
                        else {
                            Write-Host "Added hidden sheet: $($srcSheet.Name)"
                        }
                    }
                }
            }
            finally {
                $wbAdd.Close($false)
            }
        }
        catch {
            Write-Host "WARN: failed to add sheets from '$($appendFile.Name)': $($_.Exception.Message)"
        }
    }

    $vbproj = $null
    try {
        $vbproj = $wb.VBProject
    }
    catch {
        $vbproj = $null
    }

    if (-not $vbproj) {
        Write-Host "ERROR: cannot access VBA project (enable 'Trust access to the VBA project object model' in Excel Trust Center)."
        exit 1
    }

    foreach ($comp in @($vbproj.VBComponents)) {
        if ($comp.Name -eq $moduleName) {
            $vbproj.VBComponents.Remove($comp)
        }
    }
    $moduleCode = Get-Content -Path $moduleFile.FullName -Raw -Encoding UTF8
    $newComp = $vbproj.VBComponents.Add(1)
    $newComp.Name = $moduleName
    $newComp.CodeModule.AddFromString($moduleCode)

    $twComp = $vbproj.VBComponents.Item('ThisWorkbook')
    $codeModule = $twComp.CodeModule
    if ($codeModule.CountOfLines -gt 0) {
        $codeModule.DeleteLines(1, $codeModule.CountOfLines)
    }
    $newCode = Get-Content -Path $thisWorkbookFile.FullName -Raw -Encoding UTF8
    $codeModule.AddFromString($newCode)

    $buttonNames = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($code in @($moduleCode, $newCode)) {
        foreach ($m in [regex]::Matches($code, 'CreateButton\s+\S+\s*,\s*"([^"]+)"')) {
            [void]$buttonNames.Add($m.Groups[1].Value)
        }
    }
    if ($buttonNames.Count -gt 0) {
        try {
            foreach ($sheet in @($wb.Sheets)) {
                foreach ($shp in @($sheet.Shapes)) {
                    if ($buttonNames.Contains($shp.Name)) { $shp.Delete() }
                }
            }
        }
        catch {
        }
    }

    $wb.Save()
    Write-Host "Done: $($xlsmFile.Name)"
}
catch {
    Write-Host "ERROR: $($xlsmFile.Name) - $($_.Exception.Message)"
    exit 1
}
finally {
    if ($wb) { $wb.Close($false) }
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
}
