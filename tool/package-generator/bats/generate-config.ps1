# =========================================
# クライアント用パッケージ定義ファイル生成
# =========================================

param(
    [string]$SourcePath,
    [string]$TargetConfigFilePath,
    [string]$Force = "",
    [string]$LogPath,
    [string]$LogPrefix,
    [string]$ClientName = ""
)
$newLine = [Environment]::NewLine
$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $scriptDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}
$startTime = Get-Date

if (!$SourcePath) {
    Write-MessageError "SourcePath を指定してください"
    exit 1
}

if (!(Test-Path -LiteralPath $SourcePath)) {
    Write-MessageError "存在しません：$SourcePath"
    exit 1
}

if (!$TargetConfigFilePath) {
    Write-MessageError "TargetConfigFilePath を指定してください"
    exit 1
}

if (!$LogPath) {
    Write-MessageError "LogPath を指定してください"
    exit 1
}

if ((Test-Path -LiteralPath $TargetConfigFilePath) -and $Force -ne "1") {
    Write-MessageError "すでに存在します：$TargetConfigFilePath"
    Write-MessageError "上書きする場合は force:1 を指定してください"
    exit 1
}

New-Item -ItemType Directory -Path $LogPath -Force | Out-Null

$logNamePrefix = "$($LogPrefix)$(if ($ClientName) { "${ClientName}_" } else { "${defaultClientLabel}_" })$(Split-Path $TargetConfigFilePath -Leaf)"
$logFilePath = New-WorkerLogPath -LogRoot $LogPath -Prefix $logNamePrefix -Timestamp $startTime

$script:exitCode = 0
& {
    $prevEap = $ErrorActionPreference
    $excel = $null
    $workbook = $null
    try {
        $ErrorActionPreference = "Stop"

        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $excel.ScreenUpdating = $false
        $excel.EnableEvents = $false

        $workbook = $excel.Workbooks.Open($TargetConfigFilePath)
        $ws = $workbook.Worksheets.Item("テンプレート")

        $sourceCell = Get-CellByKey -Sheet $ws -Key "取得元（フルパス）" -WholeMatch -ErrorOnMissing
        $headerRow = $sourceCell.Row
        $sourceCol = $sourceCell.Column

        $noCell = Get-CellByKey -Sheet $ws -Key "No" -WholeMatch
        $noCol = if ($noCell) { $noCell.Column } else { $null }

        $usedRange = $ws.UsedRange
        $lastRow = $usedRange.Row + $usedRange.Rows.Count - 1
        $lastCol = $usedRange.Column + $usedRange.Columns.Count - 1

        if ($lastRow -gt $headerRow) {
            $clearLastCol = [Math]::Max($lastCol, $sourceCol)
            $ws.Range($ws.Cells.Item($headerRow + 1, 1), $ws.Cells.Item($lastRow, $clearLastCol)).ClearContents()
        }

        $sourcePathTrimmed = $SourcePath.TrimEnd('\')
        $files = @(Get-ChildItem -LiteralPath $SourcePath -Recurse -File)

        $resultLines = @()
        $row = $headerRow + 1
        foreach ($file in $files) {
            $relativePath = ".\" + $file.FullName.Substring($sourcePathTrimmed.Length).TrimStart('\')
            $ws.Cells.Item($row, $sourceCol).Value2 = $relativePath
            if ($noCol) {
                $ws.Cells.Item($row, $noCol).Value2 = [double]($row - $headerRow)
            }
            $resultLines += $relativePath
            $row++
        }

        $workbook.Save()
        $resultText = $resultLines -join "$newLine"
        Write-MessageComplete "テンプレートを更新しました：$TargetConfigFilePath$newLine$resultText"
    } catch {
        Write-MessageError "テンプレートの更新に失敗しました：$TargetConfigFilePath$newLine$($_.Exception.Message)"
        $script:exitCode = 1
    } finally {
        if ($workbook) { $workbook.Close($true) }
        if ($excel) { $excel.Quit() }
        if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        $ErrorActionPreference = $prevEap
    }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-MessageComplete "ログを出力しました: $logFilePath"
exit $script:exitCode
