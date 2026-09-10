param(
    [string]$TargetPath
)

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $TargetPath) {
    $xlsmFiles = Get-ChildItem -Path $dir -Filter '*.xlsm' | Where-Object { $_.Name -notlike '~$*' }
    if ($xlsmFiles.Count -ne 1) {
        Write-Host "Could not auto-detect a single .xlsm file in $dir (found $($xlsmFiles.Count)). Pass -TargetPath explicitly."
        exit 1
    }
    $TargetPath = $xlsmFiles[0].FullName
}

# .bas file naming rule: "<xlsm base name>_<module name>.bas"
$xlsmBaseName = [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)

$thisWorkbookFile = Get-ChildItem -Path $dir -Filter "${xlsmBaseName}_ThisWorkbook.bas" | Select-Object -First 1
if (-not $thisWorkbookFile) { Write-Host "ERROR: '${xlsmBaseName}_ThisWorkbook.bas' not found in $dir"; exit 1 }

$moduleFile = Get-ChildItem -Path $dir -Filter "${xlsmBaseName}_*.bas" | Where-Object { $_.FullName -ne $thisWorkbookFile.FullName } | Select-Object -First 1
if (-not $moduleFile) { Write-Host "ERROR: no '${xlsmBaseName}_<ModuleName>.bas' file found in $dir"; exit 1 }

# Module name is whatever follows "<xlsm base name>_" in the file name
$moduleName = $moduleFile.BaseName.Substring($xlsmBaseName.Length + 1)

Write-Host "Target workbook  : $TargetPath"
Write-Host "Module source    : $($moduleFile.FullName)  ->  module name: $moduleName"
Write-Host "ThisWorkbook src : $($thisWorkbookFile.FullName)"

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $null

try {
    $wb = $excel.Workbooks.Open($TargetPath)

    $vbproj = $null
    try {
        $vbproj = $wb.VBProject
    }
    catch {
        $vbproj = $null
    }

    if (-not $vbproj) {
        throw "Cannot access the VBA project (VBProject was null). In Excel: File > Options > Trust Center > Trust Center Settings > Macro Settings > check 'Trust access to the VBA project object model', then run this again."
    }

    # --- Replace the standard module ---
    # Read as UTF-8 and inject via AddFromString rather than VBComponents.Import(),
    # since Import() relies on Excel's own file-encoding detection and can mojibake.
    foreach ($comp in @($vbproj.VBComponents)) {
        if ($comp.Name -eq $moduleName) {
            $vbproj.VBComponents.Remove($comp)
        }
    }
    $moduleCode = Get-Content -Path $moduleFile.FullName -Raw -Encoding UTF8
    $newComp = $vbproj.VBComponents.Add(1)   # 1 = vbext_ct_StdModule
    $newComp.Name = $moduleName
    $newComp.CodeModule.AddFromString($moduleCode)

    # --- Replace ThisWorkbook code ---
    $twComp = $vbproj.VBComponents.Item('ThisWorkbook')
    $codeModule = $twComp.CodeModule
    if ($codeModule.CountOfLines -gt 0) {
        $codeModule.DeleteLines(1, $codeModule.CountOfLines)
    }
    $newCode = Get-Content -Path $thisWorkbookFile.FullName -Raw -Encoding UTF8
    $codeModule.AddFromString($newCode)

    $wb.Save()
    Write-Host "Done. Macros imported and workbook saved."
}
finally {
    if ($wb) { $wb.Close($false) }
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
}
