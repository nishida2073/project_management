param(
    [string]$XlsmPath,
    [string]$SheetName = "計画算定シート",
    [string]$Range = "D5:AG5000",
    [string]$BackupDir
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $XlsmPath) {
    $XlsmPath = Join-Path (Split-Path -Parent $scriptDir) '原価管理シート.xlsm'
}
$XlsmPath = (Resolve-Path -Path $XlsmPath).ProviderPath

if (-not $BackupDir) {
    $BackupDir = Join-Path $scriptDir 'backup'
}
if (-not (Test-Path -Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}
$backupName = "{0}_{1}{2}" -f `
    [System.IO.Path]::GetFileNameWithoutExtension($XlsmPath), `
    (Get-Date -Format 'yyyyMMdd-HHmmss'), `
    [System.IO.Path]::GetExtension($XlsmPath)
$backupPath = Join-Path $BackupDir $backupName
Copy-Item -Path $XlsmPath -Destination $backupPath
Write-Host "Backup created: $backupPath"

function Get-BgrColor {
    param([int]$R, [int]$G, [int]$B)
    return $R + ($G * 256) + ($B * 65536)
}

$xlExpression = 2

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

$wb = $null
try {
    $wb = $excel.Workbooks.Open($XlsmPath)
    $ws = $wb.Sheets($SheetName)

    $ws.Cells.FormatConditions.Delete() | Out-Null

    $rng = $ws.Range($Range)

    $fcSales = $rng.FormatConditions.Add($xlExpression, 0, '=$Q5="売上"')
    $fcSales.Interior.Color = Get-BgrColor -R 221 -G 235 -B 247
    $fcSales.StopIfTrue = $false

    $fcActual = $rng.FormatConditions.Add($xlExpression, 0, '=$S5="実績"')
    $fcActual.Interior.Color = Get-BgrColor -R 252 -G 228 -B 214
    $fcActual.StopIfTrue = $false

    $wb.Save()
    Write-Host "Saved: $XlsmPath"
    Write-Host "FormatConditions count on $SheetName : $($rng.FormatConditions.Count)"
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($wb) { $wb.Close($false) }
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
}
