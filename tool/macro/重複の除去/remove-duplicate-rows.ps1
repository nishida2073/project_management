param(
    [string]$XlsmPath,
    [string]$LogDir,
    [string]$BackupDir,
    [string]$SheetName = "計画算定シート",
    [string[]]$KeyColumns = @("年度", "案件ID", "案件名", "会計区分1", "会計区分2", "予実"),
    [int]$HeaderRow = 4
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $LogDir) {
    $LogDir = Join-Path $scriptDir 'logs'
}
if (-not (Test-Path -Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}
$LogFile = Join-Path $LogDir ("remove-duplicate-rows_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

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
$backupName = "{0}_{1}{2}" -f `
    [System.IO.Path]::GetFileNameWithoutExtension($XlsmPath), `
    (Get-Date -Format 'yyyyMMdd-HHmmss'), `
    [System.IO.Path]::GetExtension($XlsmPath)
$backupPath = Join-Path $BackupDir $backupName
Copy-Item -Path $XlsmPath -Destination $backupPath
Write-Log "Backup created: $backupPath"
Write-Log "Target workbook : $XlsmPath"
Write-Log "Key columns     : $($KeyColumns -join ', ')"

function Get-ColumnIndexByHeader {
    param($Worksheet, [string]$HeaderText, [int]$HeaderRow)
    $xlToLeft = -4159
    $lastCol = $Worksheet.Cells.Item($HeaderRow, $Worksheet.Columns.Count).End($xlToLeft).Column
    for ($c = 1; $c -le $lastCol; $c++) {
        if ("$($Worksheet.Cells.Item($HeaderRow, $c).Value2)".Trim() -eq $HeaderText.Trim()) {
            return $c
        }
    }
    throw "ヘッダー「$HeaderText」が$HeaderRow行目に見つかりません。"
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$excel.EnableEvents = $false

$wb = $null
try {
    $wb = $excel.Workbooks.Open($XlsmPath)
    $wsMain = $wb.Sheets.Item($SheetName)

    $keyColIndexes = @($KeyColumns | ForEach-Object { Get-ColumnIndexByHeader -Worksheet $wsMain -HeaderText $_ -HeaderRow $HeaderRow })

    $xlUp = -4162
    $lastRow = $wsMain.Cells.Item($wsMain.Rows.Count, $keyColIndexes[0]).End($xlUp).Row

    $removedCount = 0
    $deletedRowsByKeptRow = [ordered]@{}

    if ($lastRow -ge 5) {
        $colValues = @{}
        foreach ($idx in ($keyColIndexes | Select-Object -Unique)) {
            $colValues[$idx] = $wsMain.Range($wsMain.Cells.Item(1, $idx), $wsMain.Cells.Item($lastRow, $idx)).Value2
        }

        $firstRowByKey = @{}
        $rowsToDelete = New-Object System.Collections.Generic.List[int]

        for ($r = 5; $r -le $lastRow; $r++) {
            $keyParts = @($keyColIndexes | ForEach-Object { "$($colValues[$_][$r, 1])".Trim() })
            if ($keyParts -contains "") { continue }

            $key = $keyParts -join "|"
            if ($firstRowByKey.ContainsKey($key)) {
                $rowsToDelete.Add($r)
                $keptRowKey = "$($firstRowByKey[$key])"
                if (-not $deletedRowsByKeptRow.Contains($keptRowKey)) {
                    $deletedRowsByKeptRow[$keptRowKey] = New-Object System.Collections.Generic.List[int]
                }
                $deletedRowsByKeptRow[$keptRowKey].Add($r)
            } else {
                $firstRowByKey[$key] = $r
            }
        }

        $removedCount = $rowsToDelete.Count
        if ($removedCount -gt 0) {
            foreach ($r in ($rowsToDelete | Sort-Object -Descending)) {
                $wsMain.Rows($r).Delete() | Out-Null
            }
        }
    }

    Write-Log "重複行の削除が完了しました。"
    Write-Log "削除行数：$removedCount"
    Write-Log ""
    foreach ($keptRowKey in $deletedRowsByKeptRow.Keys) {
        Write-Log "残した行：$keptRowKey"
        Write-Log "削除した行：$($deletedRowsByKeptRow[$keptRowKey] -join ',')"
    }

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

    if ($wsMain) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wsMain) | Out-Null }
    if ($wb) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wb) | Out-Null }
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
