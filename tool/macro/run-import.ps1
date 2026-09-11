param(
    [string]$DataDir,
    [string]$XlsmPath,
    [string]$LogDir
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $DataDir) {
    $DataDir = Join-Path $scriptDir '実績データ'
}
$DataDir = (Resolve-Path -Path $DataDir).ProviderPath

if (-not $LogDir) {
    $LogDir = Join-Path $scriptDir 'logs'
}
if (-not (Test-Path -Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}
$LogFile = Join-Path $LogDir ("run-import_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

if (-not $XlsmPath) {
    $xlsmFiles = Get-ChildItem -Path $scriptDir -Filter '*.xlsm' | Where-Object { $_.Name -notlike '~$*' }
    if ($xlsmFiles.Count -ne 1) {
        Write-Log "ERROR: could not auto-detect a single .xlsm file in $scriptDir (found $($xlsmFiles.Count)). Pass -XlsmPath explicitly."
        exit 1
    }
    $XlsmPath = $xlsmFiles[0].FullName
}
$XlsmPath = (Resolve-Path -Path $XlsmPath).ProviderPath

$dataFiles = Get-ChildItem -Path $DataDir -Filter '*.xlsx' | Where-Object { $_.Name -notlike '~$*' } | Sort-Object LastWriteTime
if ($dataFiles.Count -eq 0) {
    Write-Log "ERROR: no .xlsx file found in $DataDir."
    exit 1
}

Write-Log "Target workbook : $XlsmPath"
Write-Log "Data files (oldest to newest; newest wins on overlap):"
foreach ($f in $dataFiles) {
    Write-Log "  $($f.FullName) (LastWriteTime: $($f.LastWriteTime))"
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$excel.EnableEvents = $false

$wb = $null
try {
    $wb = $excel.Workbooks.Open($XlsmPath)

    foreach ($dataFile in $dataFiles) {
        Write-Log "---"
        Write-Log "Processing: $($dataFile.FullName)"
        $result = $excel.Run("'$($wb.Name)'!ImportFromOtherBook", $dataFile.FullName)
        Write-Log $result
    }
    Write-Log "---"

    $excel.Run("'$($wb.Name)'!HandleBeforeSave") | Out-Null
    $wb.Save()
    Write-Log "Saved: $XlsmPath"
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($wb) { $wb.Close($false) }
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
}
