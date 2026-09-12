param(
    [string]$XlsmPath,
    [string]$MacroDir,
    [string]$BackupDir,
    [string]$LogDir
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $LogDir) {
    $LogDir = Join-Path $scriptDir 'logs'
}
if (-not (Test-Path -Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}
$LogFile = Join-Path $LogDir ("import-macros_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

if (-not $MacroDir) {
    $MacroDir = Join-Path $scriptDir '..\macros'
}
$MacroDir = (Resolve-Path -Path $MacroDir).ProviderPath

if (-not $XlsmPath) {
    $xlsmFiles = Get-ChildItem -Path $scriptDir\.. -Filter '*.xlsm' | Where-Object { $_.Name -notlike '~$*' }
    if ($xlsmFiles.Count -ne 1) {
        Write-Log "ERROR: could not auto-detect a single .xlsm file in $scriptDir\.. (found $($xlsmFiles.Count)). Pass -XlsmPath explicitly."
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
    Write-Log "ERROR: no '${xlsmBaseName}_ThisWorkbook.bas' in $MacroDir"
    exit 1
}

$moduleFile = Get-ChildItem -Path $MacroDir -Filter "${xlsmBaseName}_*.bas" | Where-Object { $_.FullName -ne $thisWorkbookFile.FullName } | Select-Object -First 1
if (-not $moduleFile) {
    Write-Log "ERROR: no '${xlsmBaseName}_<ModuleName>.bas' in $MacroDir"
    exit 1
}

$moduleName = $moduleFile.BaseName.Substring($xlsmBaseName.Length + 1)

Write-Log "Target workbook  : $($xlsmFile.FullName)"
Write-Log "Module source    : $($moduleFile.FullName)  ->  module name: $moduleName"
Write-Log "ThisWorkbook src : $($thisWorkbookFile.FullName)"

$backupName = "{0}_{1}{2}" -f `
    $xlsmFile.BaseName, `
    (Get-Date -Format 'yyyyMMdd-HHmmss'), `
    $xlsmFile.Extension
$backupPath = Join-Path $BackupDir $backupName
Copy-Item -Path $xlsmFile.FullName -Destination $backupPath
Write-Log "Backup created   : $backupPath"

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
                            Write-Log "WARN: could not hide sheet '$($srcSheet.Name)' (Visible=$($newSheet.Visible))"
                        }
                        else {
                            Write-Log "Added hidden sheet: $($srcSheet.Name)"
                        }
                    }
                }
            }
            finally {
                $wbAdd.Close($false)
            }
        }
        catch {
            Write-Log "WARN: failed to add sheets from '$($appendFile.Name)': $($_.Exception.Message)"
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
        Write-Log "ERROR: cannot access VBA project (enable 'Trust access to the VBA project object model' in Excel Trust Center)."
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
    Write-Log "Done: $($xlsmFile.Name)"
}
catch {
    Write-Log "ERROR: $($xlsmFile.Name) - $($_.Exception.Message)"
    exit 1
}
finally {
    if ($wb) { $wb.Close($false) }
    $excel.Quit()

    if ($wb) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wb) | Out-Null }
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
