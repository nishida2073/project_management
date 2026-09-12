param(
    [string]$XlsmPath,
    [string]$SheetName = "計画算定シート",
    [array]$Rules = @(
        @{ Range = "D5:AG5000"; Formula = '=$Q5="売上"'; Color = "#DDEBF7" },
        @{ Range = "D5:AG5000"; Formula = '=$S5="実績"'; Color = "#FCE4D6" }
    ),
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

function Get-BgrColorFromHex {
    param([string]$Hex)
    $Hex = $Hex.TrimStart('#')
    $r = [Convert]::ToInt32($Hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($Hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($Hex.Substring(4, 2), 16)
    return $r + ($g * 256) + ($b * 65536)
}

$xlExpression = 2

$msoAutomationSecurityForceDisable = 3

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$excel.AutomationSecurity = $msoAutomationSecurityForceDisable
$excel.EnableEvents = $false

$wb = $null
try {
    $wb = $excel.Workbooks.Open($XlsmPath)
    $ws = $wb.Sheets($SheetName)

    $ws.Cells.FormatConditions.Delete() | Out-Null

    foreach ($rule in $Rules) {
        $rng = $ws.Range($rule.Range)
        $fc = $rng.FormatConditions.Add($xlExpression, 0, $rule.Formula)
        $fc.Interior.Color = Get-BgrColorFromHex $rule.Color
        $fc.StopIfTrue = $false
    }

    $ws.Activate()
    $ws.Range("A1").Select() | Out-Null

    $wb.Save()
    Write-Host "Saved: $XlsmPath"
    Write-Host "FormatConditions count on $SheetName : $($ws.Cells.FormatConditions.Count)"
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($wb) { $wb.Close($false) }
    $excel.Quit()

    # ワークシート等のCOMオブジェクト参照が残っていると、Quit()してもEXCEL.EXEプロセスの終了に
    # 数秒かかることがあるため、明示的に解放してからガベージコレクションを走らせる
    if ($ws) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ws) | Out-Null }
    if ($wb) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wb) | Out-Null }
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
