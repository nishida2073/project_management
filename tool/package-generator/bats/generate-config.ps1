# =========================================
# クライアント用パッケージ定義ファイル生成
# =========================================

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $scriptDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}
$basePath = Split-Path $scriptDir -Parent

$clientName = $env:CLIENT_NAME
$sourcePath = $env:GENERATE_SOURCE_PATH

if (!$clientName) {
    Write-MessageError "CLIENT_NAME が指定されていません（generate-config.bat client:<クライアント名> のように指定してください）"
    exit 1
}

if (!$sourcePath) {
    Write-MessageError "GENERATE_SOURCE_PATH を set-env.bat で設定してください"
    exit 1
}

if (!(Test-Path -LiteralPath $sourcePath)) {
    Write-MessageError "存在しません：$sourcePath"
    exit 1
}

$templatePath = Join-Path $basePath "config\package_definition.xlsx"
if (!(Test-Path -LiteralPath $templatePath)) {
    Write-MessageError "テンプレートが見つかりません：$templatePath"
    exit 1
}

$destPath = Join-Path (Split-Path $templatePath -Parent) "package_definition_$clientName.xlsx"

if ((Test-Path -LiteralPath $destPath) -and $env:FORCE -ne "1") {
    Write-MessageError "すでに存在します：$destPath"
    Write-MessageError "上書きする場合は force:1 を指定してください"
    exit 1
}

Copy-Item -LiteralPath $templatePath -Destination $destPath -Force

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

    $workbook = $excel.Workbooks.Open($destPath)
    $ws = $workbook.Worksheets.Item(1)

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

    $sourcePathTrimmed = $sourcePath.TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $sourcePath -Recurse -File)

    $row = $headerRow + 1
    foreach ($file in $files) {
        $relativePath = ".\" + $file.FullName.Substring($sourcePathTrimmed.Length).TrimStart('\')
        $ws.Cells.Item($row, $sourceCol).Value2 = $relativePath
        if ($noCol) {
            $ws.Cells.Item($row, $noCol).Value2 = [double]($row - $headerRow)
        }
        $row++
    }

    $workbook.Save()

    Write-MessageComplete "作成しました：$destPath（$($files.Count)件）"
} catch {
    Write-MessageError "処理に失敗しました：$($_.Exception.Message)"
    exit 1
} finally {
    if ($workbook) { $workbook.Close($true) }
    if ($excel) { $excel.Quit() }
    if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
    if ($excel) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    $ErrorActionPreference = $prevEap
}
