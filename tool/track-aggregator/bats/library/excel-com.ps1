Add-Type -AssemblyName System.Drawing

function Convert-ExcelToCsvString {
    param(
        [Parameter(Mandatory)]
        [string]$ExcelFilePath,
        [int]$SheetIndex = 1,
        [int]$HeaderRowIndex = 1,
        [int[]]$DateColumnIndexes = @(),
        [string]$Delimiter = "`t"
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $excel.ScreenUpdating = $false
    $excel.EnableEvents = $false

    try {
        $workbook = $excel.Workbooks.Open($ExcelFilePath)
        if ($SheetIndex -eq -1) {
            $SheetIndex = $workbook.Sheets.Count
        }
        $sheet = $workbook.Sheets.Item($SheetIndex)
        $data  = $sheet.UsedRange.Value2
        $rows = $data.GetLength(0)
        $cols = $data.GetLength(1)
        $isDateCol = New-Object bool[] ($cols + 1)
        foreach ($i in $DateColumnIndexes) {
            if ($i -le $cols) { $isDateCol[$i] = $true }
        }
        $csvLines = New-Object System.Collections.Generic.List[string]
        for ($r = 1; $r -le $rows; $r++) {
            $sb = [System.Text.StringBuilder]::new(256)
            $isEmpty = $true
            for ($c = 1; $c -le $cols; $c++) {
                if ($c -gt 1) { $null = $sb.Append($Delimiter) }
                $value = $data[$r, $c]
                if ($null -eq $value) { continue }
                if ($r -gt $HeaderRowIndex -and $isDateCol[$c] -and $value -is [double]) {
                    $text = ([DateTime]::FromOADate($value)).ToString("yyyy-MM-dd")
                }
                else {
                    $text = [string]$value
                }
                if ($text.Length -gt 0) {
                    $isEmpty = $false
                    $null = $sb.Append($text)
                }
            }
            if (-not $isEmpty) {
                $csvLines.Add($sb.ToString())
            }
        }
        Write-Message $csvLines -VarName "csvLines"
        return $csvLines
    }
    finally {
        if ($sheet)     { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) }
        if ($workbook)  { $workbook.Close($false); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel)     { $excel.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    }
}


function Set-CellColorByBoolean {
    param (
        [Parameter(Mandatory)]
        $Range,
        [string]$TrueLabel = "TRUE",
        [string]$FalseLabel = "FALSE"
    )
    $fc = $Range.FormatConditions
    $fc.Delete()

    $addr = $Range.Cells(1,1).Address($false,$false)

    $c1 = $fc.Add(
        [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
        $null,
        "=OR($addr=TRUE,$addr=""$TrueLabel"")"
    )
    $c1.Font.Color = 32768

    $c2 = $fc.Add(
        [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
        $null,
        "=OR($addr=FALSE,$addr=""$FalseLabel"")"
    )
    $c2.Font.Color = 255
}

function Set-CellColorByValue {
    param (
        $Range,
        [double]$Threshold
    )
    $fc = $Range.FormatConditions
    $fc.Delete()
    $addr = $Range.Cells(1,1).Address($false,$false)

    $c1 = $fc.Add(
        [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
        $null,
        "=AND(ISNUMBER($addr),$addr>$Threshold)"
    )
    $c1.Font.Color = 32768

    $c2 = $fc.Add(
        [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
        $null,
        "=AND(ISNUMBER($addr),$addr<$Threshold)"
    )
    $c2.Font.Color = 255
}

function Set-CellColorByWord {
    param (
        $Range,
        [string]$CompareValue
    )
    $fc = $Range.FormatConditions
    $fc.Delete()
    $addr = $Range.Cells(1,1).Address($false,$false)
    $compare = '"' + $CompareValue + '"'
    $c1 = $fc.Add(
        [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
        $null,
        "=$addr=$compare"
    )
    $c1.Font.Color = 32768

    $c2 = $fc.Add(
        [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
        $null,
        "=$addr<>$compare"
    )
    $c2.Font.Color = 255
}


function Set-CellColorByRowComparison {
    param (
        $Range,
        [int]$TotalRowIndex,
        [int]$BlockSize = 9,
        [int]$SkipInBlock = 4
    )

    $fc = $Range.FormatConditions
    $fc.Delete()

    $sheet = $Range.Worksheet

    $startRow = $Range.Row
    $endRow   = $Range.Row + $Range.Rows.Count - 1
    $startCol = $Range.Column
    $endCol   = $Range.Column + $Range.Columns.Count - 1
    for ($blockStart = $startCol; $blockStart -le $endCol; $blockStart += $BlockSize) {
        $compareStart = $blockStart + $SkipInBlock
        if ($compareStart -gt $endCol) { break }

        $compareEnd = [Math]::Min($blockStart + $BlockSize - 1, $endCol)

        $range = $sheet.Range(
            $sheet.Cells($startRow, $compareStart),
            $sheet.Cells($endRow,   $compareEnd)
        )

        $formulaOK = "=RC>R" + $TotalRowIndex + "C"
        $c1 = $range.FormatConditions.Add(
            [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
            $null,
            $formulaOK
        )
        $c1.Font.Color = 32768

        $formulaNG   = "=RC<R"  + $TotalRowIndex + "C"
        $c2 = $range.FormatConditions.Add(
            [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
            $null,
            $formulaNG
        )
        $c2.Font.Color = 255
    }
}


function Scroll-ToIndex {
    param(
        [Parameter(Mandatory=$true)]
        $Sheet,
        [int]$ColumnIndex = -1,
        [int]$RowIndex = -1
    )
    $window = $Sheet.Application.ActiveWindow
    if ($ColumnIndex -gt 0) {
        $window.ScrollColumn = $ColumnIndex
    }
    if ($RowIndex -gt 0) {
        $window.ScrollRow = $RowIndex
    }
}



function Get-CellByKey {
    param(
        [Parameter(Mandatory)]
        $Sheet,
        [Parameter(Mandatory)]
        [string]$Key,
        [switch]$WholeMatch,
        [switch]$ErrorOnMissing
    )
    $usedRange = $Sheet.UsedRange
    if (-not $usedRange) {
        if ($ErrorOnMissing) {
            throw "シートにデータが存在しません。"
        } else {
            return $null
        }
     }
    $xlValues        = -4163
    $xlWhole         = 1
    $xlPart          = 2
    $xlByRows        = 1
    $xlNext          = 1
    $lookAt = if ($WholeMatch) { $xlWhole } else { $xlPart }

    $cell = $usedRange.Find(
        $Key,
        [Type]::Missing,
        $xlValues,
        $lookAt,
        $xlByRows,
        $xlNext,
        $false
    )
    if (-not $cell) {
        if ($ErrorOnMissing) {
            throw "キー '$Key' はシート内に見つかりません。"
        } else {
            return $null
        }
    }
    return $cell
}

function Write-BodyDatas {
    param(
        $StartCell,
        $Datas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    if (-not $Datas) {
        return
    }
    if ($Datas -isnot [object[,]] -and $Datas[0] -isnot [System.Array]) {
        $Datas = ,$Datas
    }

    $sheet    = $StartCell.Worksheet
    $startRow = $StartCell.Row
    $startCol = $StartCell.Column

    if ($Datas -is [object[,]]) {
        $excelDatas = $Datas
        $rowCount = $Datas.GetLength(0)
        $colCount = $Datas.GetLength(1)
    } else {
        $rowCount = $Datas.Count
        if ($rowCount -eq 0) {
            return
        }
        $colCount = $Datas[0].Count
        $excelDatas = New-Object 'object[,]' $rowCount, $colCount
        for ($r = 0; $r -lt $rowCount; $r++) {
            $row = $Datas[$r]
            for ($c = 0; $c -lt $colCount; $c++) {
                $excelDatas[$r, $c] = $row[$c]
            }
        }
    }

    $range = $sheet.Range(
        $StartCell,
        $sheet.Cells.Item(
            $startRow + $rowCount - 1,
            $startCol + $colCount - 1
        )
    )

    $range.Value2 = $excelDatas
}


function Set-AutoFit {
    param(
        [Parameter(Mandatory)]
        $Sheet
    )
    $Sheet.UsedRange.Rows.AutoFit() | Out-Null
}

function Set-AutoFilter {
    param(
        [Parameter(Mandatory)]
        $Range,
        [int]$FieldIndex,
        [string]$Criteria
    )
    if ($PSBoundParameters.ContainsKey('FieldIndex') -and
        $PSBoundParameters.ContainsKey('Criteria')) {
        $Range.AutoFilter($FieldIndex, $Criteria) | Out-Null
    }
    else {
        if (-not $Range.Parent.AutoFilterMode) {
            $Range.AutoFilter() | Out-Null
        }
    }
}


function Remove-Sheet {
    param(
        [Parameter(Mandatory)]
        [object]$Workbook,
        [Parameter(Mandatory)]
        [string]$SheetName
    )
    try {
        $existingSheet = $Workbook.Sheets.Item($SheetName)
    } catch {
        $existingSheet = $null
    }
    if ($existingSheet) {
        $existingSheet.Delete()
    }
}

function Set-SheetFirstCell {
    param(
        [Parameter(Mandatory)]
        [object]$Sheet
    )
    $Sheet.Activate() | Out-Null
    $Sheet.Range("A1").Select() | Out-Null
}

function Set-FirstVisibleSheet {
    param(
        [Parameter(Mandatory)]
        [object]$Workbook
    )
    $visibleSheet = $Workbook.Worksheets |
        Where-Object { $_.Visible -eq -1 } |
        Select-Object -First 1
    if ($visibleSheet) {
        $visibleSheet.Activate() | Out-Null
        $visibleSheet.Range("A1").Select() | Out-Null
    }
}


function Expand-ColumnsFromTemplate {
    param(
        [Parameter(Mandatory)]
        $Sheet,
        [Parameter(Mandatory)]
        [int]$TemplateStartColumn,
        [int]$ColumnsPerSet = 1,
        [Parameter(Mandatory)]
        [int]$TotalSets,
        [switch]$InsertBeforeCopy
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    if ($TotalSets -le 1) { return }

    $used = $Sheet.UsedRange
    $lastRow = $used.Row + $used.Rows.Count - 1

    $sourceRange = $Sheet.Range(
        $Sheet.Cells(1, $TemplateStartColumn),
        $Sheet.Cells($lastRow, $TemplateStartColumn + $ColumnsPerSet - 1)
    )
    $totalCols = $ColumnsPerSet * $TotalSets

    if ($InsertBeforeCopy) {
        $insertCols = $totalCols - $ColumnsPerSet
        if ($insertCols -gt 0) {
            $insertRange = $Sheet.Range(
                $Sheet.Cells(1, $TemplateStartColumn + $ColumnsPerSet),
                $Sheet.Cells(1, $TemplateStartColumn + $ColumnsPerSet + $insertCols - 1)
            )
            $insertRange.EntireColumn.Insert() | Out-Null
        }
    }

    $destinationRange = $Sheet.Range(
        $Sheet.Cells(1, $TemplateStartColumn),
        $Sheet.Cells($lastRow, $TemplateStartColumn + $totalCols - 1)
    )

    Use-Mutex "ExcelCopyPasteLock" {
        $sourceRange.Copy() | Out-Null
        $destinationRange.PasteSpecial(-4123) | Out-Null
        $destinationRange.PasteSpecial(13) | Out-Null
    }

    for ($j = 0; $j -lt $ColumnsPerSet; $j++) {
        $w = $Sheet.Columns($TemplateStartColumn + $j).ColumnWidth
        for ($i = 0; $i -lt $TotalSets; $i++) {
            $Sheet.Columns($TemplateStartColumn + $j + ($i * $ColumnsPerSet)).ColumnWidth = $w
        }
    }
}


function Expand-RowsFromTemplate {
    param(
        [Parameter(Mandatory)]
        $Sheet,
        [Parameter(Mandatory)]
        [int]$TemplateStartRow,
        [int]$RowsPerSet = 1,
        [Parameter(Mandatory)]
        [int]$TotalSets,
        [switch]$InsertBeforeCopy
    )

    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    if ($TotalSets -le 1) { return }
    $used = $Sheet.UsedRange
    $lastColumn = $used.Column + $used.Columns.Count - 1
    $sourceRange = $Sheet.Range(
        $Sheet.Cells($TemplateStartRow, 1),
        $Sheet.Cells($TemplateStartRow + $RowsPerSet - 1, $lastColumn)
    )
    $totalRows = $RowsPerSet * $TotalSets

    if ($InsertBeforeCopy) {
        $insertRows = $totalRows - $RowsPerSet
        if ($insertRows -gt 0) {
            $insertRange = $Sheet.Range(
                $Sheet.Cells($TemplateStartRow + $RowsPerSet, 1),
                $Sheet.Cells($TemplateStartRow + $RowsPerSet + $insertRows - 1, 1)
            )
            $insertRange.EntireRow.Insert() | Out-Null
        }
    }

    $destinationRange = $Sheet.Range(
        $Sheet.Cells($TemplateStartRow, 1),
        $Sheet.Cells($TemplateStartRow + $totalRows - 1, $lastColumn)
    )

    Use-Mutex "ExcelCopyPasteLock" {
        $sourceRange.Copy() | Out-Null
        $destinationRange.PasteSpecial(-4123) | Out-Null
        $destinationRange.PasteSpecial(13) | Out-Null
    }

    for ($j = 0; $j -lt $RowsPerSet; $j++) {
        $h = $Sheet.Rows($TemplateStartRow + $j).RowHeight
        $start = $TemplateStartRow + $j
        for ($i = 0; $i -lt $TotalSets; $i++) {
            $Sheet.Rows($start + ($i * $RowsPerSet)).RowHeight = $h
        }
    }
}


function Merge-ConsecutiveColumn {
    param($Sheet, [int]$RowStartIndex, [array]$Rows, [int]$ColumnIndex, [scriptblock]$KeySelector)
    $mergeStartRow = $RowStartIndex
    for ($i = 1; $i -le $Rows.Count; $i++) {
        $isLastRow = ($i -eq $Rows.Count)
        $changed = $isLastRow -or ((& $KeySelector $Rows[$i]) -ne (& $KeySelector $Rows[$i - 1]))
        if ($changed) {
            $mergeEndRow = $RowStartIndex + $i - 1
            if ($mergeEndRow -gt $mergeStartRow) {
                $Sheet.Range($Sheet.Cells.Item($mergeStartRow, $ColumnIndex), $Sheet.Cells.Item($mergeEndRow, $ColumnIndex)).Merge() | Out-Null
            }
            $mergeStartRow = $RowStartIndex + $i
        }
    }
}

function Test-SheetSelected {
    param(
        [string[]]$SelectedSheets,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not $SelectedSheets -or $SelectedSheets.Count -eq 0) { return $true }
    return $SelectedSheets -contains $Name
}

function ConvertTo-SheetNameArray {
    param([string]$Sheets)
    if (-not $Sheets) { return @() }
    return @($Sheets.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function ConvertTo-OleColor {
    param([Parameter(Mandatory)][System.Drawing.Color]$Color)
    return $Color.R + ($Color.G * 256) + ($Color.B * 65536)
}

function Get-RowObjects {
    param(
        [Parameter(Mandatory)]$Sheet
    )

    $used = $Sheet.UsedRange
    $rowCount = $used.Rows.Count
    $colCount = $used.Columns.Count
    if ($rowCount -lt 2) { return @() }

    $data = $used.Value2
    $headers = @()
    for ($c = 1; $c -le $colCount; $c++) {
        $headers += "$($data[1, $c])"
    }

    $rows = @()
    for ($r = 2; $r -le $rowCount; $r++) {
        $obj = [ordered]@{}
        for ($c = 1; $c -le $colCount; $c++) {
            $obj[$headers[$c - 1]] = $data[$r, $c]
        }
        $rows += [PSCustomObject]$obj
    }
    return $rows
}

function Write-RowObjects {
    param(
        [Parameter(Mandatory)]$Sheet,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Rows,
        [string[]]$Headers = @()
    )

    $rowsToWrite = $Rows
    if ($rowsToWrite.Count -eq 0) {
        if ($Headers.Count -eq 0) { return }
        $blank = [ordered]@{}
        foreach ($h in $Headers) { $blank[$h] = $null }
        $rowsToWrite = @([PSCustomObject]$blank)
    }

    $columnNames = if ($Headers.Count -gt 0) { $Headers } else { @($rowsToWrite[0].PSObject.Properties.Name) }

    $colCount = $columnNames.Count
    $rowCount = $rowsToWrite.Count
    $excelDatas = New-Object 'object[,]' ($rowCount + 1), $colCount
    for ($c = 0; $c -lt $colCount; $c++) {
        $excelDatas[0, $c] = [string]$columnNames[$c]
    }
    for ($r = 0; $r -lt $rowCount; $r++) {
        $row = $rowsToWrite[$r]
        $excelRow = $r + 1
        for ($c = 0; $c -lt $colCount; $c++) {
            $value = $row.($columnNames[$c])
            if ($null -eq $value) {
                $excelDatas[$excelRow, $c] = ""
            } elseif ($value -is [bool] -or $value -is [double] -or $value -is [int]) {
                $excelDatas[$excelRow, $c] = $value
            } else {
                $excelDatas[$excelRow, $c] = [string]$value
            }
        }
    }
    $range = $Sheet.Range($Sheet.Cells.Item(1, 1), $Sheet.Cells.Item($rowCount + 1, $colCount))
    try {
        $range.Value2 = $excelDatas
    } catch {
        Write-Message "Write-RowObjects: Value2代入に失敗 rowCount=$rowCount colCount=$colCount rangeAddress=$($range.Address())" -ForegroundColor Red -Type "Info" -NoHeader
        throw
    }
    $Sheet.UsedRange.Columns.AutoFit() | Out-Null
}

function Set-PlaceholderRichText {
    param(
        [Parameter(Mandatory)]$Cell,
        [string]$OriginalValue,
        [Parameter(Mandatory)][string]$Replacement,
        [Parameter(Mandatory)][System.Drawing.Color]$Color
    )
    if (-not $OriginalValue -or -not $OriginalValue.Contains('{PH}')) { return }

    $segments = $OriginalValue.Split([string[]]@('{PH}'), [System.StringSplitOptions]::None)
    $Cell.Value2 = $OriginalValue.Replace('{PH}', $Replacement)

    $oleColor = ConvertTo-OleColor -Color $Color
    $pos = 0
    for ($i = 0; $i -lt $segments.Length; $i++) {
        $pos += $segments[$i].Length
        if ($i -lt $segments.Length - 1) {
            $len = $Replacement.Length
            if ($len -gt 0) {
                $chars = $Cell.Characters($pos + 1, $len)
                $chars.Font.Color = $oleColor
                $chars.Font.Bold = $true
            }
            $pos += $len
        }
    }
}

function Set-HeaderRowColor {
    param(
        [Parameter(Mandatory)]$Sheet,
        [Parameter(Mandatory)][System.Drawing.Color]$Color
    )

    $used = $Sheet.UsedRange
    if (-not $used) { return }
    $oleColor = ConvertTo-OleColor -Color $Color
    $lastCol = $used.Column + $used.Columns.Count - 1
    $headerRange = $Sheet.Range($Sheet.Cells.Item(1, 1), $Sheet.Cells.Item(1, $lastCol))
    $headerRange.Interior.Color = $oleColor
    Set-ColumnWidth -Worksheet $Sheet
}

function Set-ColumnWidth {
    param([Parameter(Mandatory)]$Worksheet)
    $used = $Worksheet.UsedRange
    if (-not $used) { return }
    $used.Columns.AutoFit() | Out-Null
    $lastCol = $used.Column + $used.Columns.Count - 1
    for ($c = 1; $c -le $lastCol; $c++) {
        $Worksheet.Columns.Item($c).ColumnWidth += 4
    }
}
