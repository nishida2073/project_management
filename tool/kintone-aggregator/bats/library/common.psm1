
function Write-Message {
    param(
        [object]$Datas,
        [string]$VarName = "Debug Message",
        [string]$Type = "Debug",
        [ConsoleColor]$ForegroundColor = "White"
    )
    if ($Type -eq "Debug") {
        return
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.ff"
    Write-Host "============== [$timestamp] $VarName ==============" -ForegroundColor $ForegroundColor
    
    if( -not $Datas ){
        Write-Host $Datas -ForegroundColor $ForegroundColor
        return
    }
    
    if ($Datas -is [PSCustomObject] -or $Datas -is [Hashtable] -or $Datas -is [array]) {
        $Datas | ConvertTo-Json -Depth 10 | ForEach-Object { Write-Host $_ -ForegroundColor $ForegroundColor }
    }
    else {
        Write-Host $Datas -ForegroundColor $ForegroundColor
    }
}


$breakLineKeyword = "BRBR"
function Convert-BreakLine {
    param(
        [Parameter(Mandatory)]
        [array]$Datas
    )
    for ($r = 0; $r -lt $Datas.Count; $r++) {
        # 2次元
        if ($Datas[$r] -is [array]) {
            for ($c = 0; $c -lt $Datas[$r].Count; $c++) {
                $val = $Datas[$r][$c]
                if ($val -is [string]) {
                    $Datas[$r][$c] = $val -replace "`n", $breakLineKeyword
                }
            }
        }
        # 1次元
        else {
            $val = $Datas[$r]
            if ($val -is [string]) {
                $Datas[$r] = $val -replace "`n", $breakLineKeyword
            }
        }
    }
    return $Datas
}


function Restore-BreakLine {
    param(
        [Parameter(Mandatory)]
        [array]$Datas
    )
    for ($r = 0; $r -lt $Datas.Count; $r++) {
        # 2次元
        if ($Datas[$r] -is [array]) {
            for ($c = 0; $c -lt $Datas[$r].Count; $c++) {
                $val = $Datas[$r][$c]
                if ($val -is [string]) {
                    $Datas[$r][$c] = $val -replace $breakLineKeyword, "`n"
                }
            }
        }
        # 1次元
        else {
            $val = $Datas[$r]
            if ($val -is [string]) {
                $Datas[$r] = $val -replace $breakLineKeyword, "`n"
            }
        }
    }
    return $Datas
}


function Convert-ExcelToCsvString {
    param(
        [Parameter(Mandatory)]
        [string]$ExcelFilePath,
        [int]$SheetIndex = 1,
        [int]$HeaderRowIndex = 1,
        [int[]]$DateColumnIndexes = @()
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
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
                if ($c -gt 1) { $null = $sb.Append(',') }
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

function ToBool($value) {
    if ($value -is [bool]) { return $value }
    if ($value -is [string]) {
        switch ($value.ToLower()) {
            "true"  { return $true }
            "false" { return $false }
        }
    }
    return $false
}


function Get-CurrentAppFieldData {
    param(
        [string]$TargetAppId,
        [string]$BaseUrl,
        [string]$Authorization
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $headers = @{
        "X-Cybozu-Authorization" = $Authorization
    }
    
    $Url = "$BaseUrl/k/v1/app/form/fields.json?app=$TargetAppId"
    try {
        $allRecords = @()
        $response = Invoke-RestMethod -Uri $Url -Headers $headers -Method GET
        Write-Message $response -VarName "response"
        return $response.properties
    } catch {
        Write-Message "フィールド取得 失敗: $($_.Exception.Message)" -VarName "message" -ForegroundColor Red
        throw
    }
}


function Get-NestedPropertyValue {
    param (
        [Parameter(Mandatory)]
        [object]$Object,
        [Parameter(Mandatory)]
        [string]$PropertyPath
    )
    $path = $PropertyPath -split '\.'
    $value = $Object
    foreach ($p in $path) {
        if ($null -eq $value) {
            return $null
        }
        $value = $value.$p
    }
    return $value
}


function Get-CurrentAppData {
    param(
        [string]$TargetAppId,
        [string]$BaseUrl,
        [string]$Authorization,
        [string]$TargetDateCodeField,
        [string]$TargetDate
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $headers = @{
        "X-Cybozu-Authorization" = $Authorization
    }
    
    $Url = "$BaseUrl/k/v1/records.json?app=$TargetAppId&query=$TargetDateCodeField=`"$TargetDate`""
    
    try {
        $allRecords = @()
        $offset = 0
        $limit = 100
        while ($true) {
            # クエリを Kintone形式で構築（$Urlは常にquery=を含む）
            $urlWithOffset = "$Url limit $limit offset $offset"
            Write-Message $urlWithOffset -VarName "urlWithOffset" -Type "Info"
            
            # API呼び出し
            $response = Invoke-RestMethod -Uri $urlWithOffset -Headers $headers -Method GET
            # レコード抽出
            if ($response.PSObject.Properties.Name -contains "records") {
                $records = $response.records
            } else {
                $records = ($response.PSObject.Properties |
                                Where-Object {
                                    $_.Value -is [System.Collections.IEnumerable] -and
                                    -not ($_.Value -is [string])
                                } |
                                Select-Object -First 1).Value
            }
            if (-not $records -or $records.Count -eq 0) {
                Write-Message "データなし" -VarName "message" -Type "Info"
                break
            }
            $allRecords += $records
            
            # 最後まで取得したら終了
            if ($records.Count -lt $limit) {
                break
            }
            # 次ページへ
            $offset += $limit
        }
        Write-Message $allRecords -VarName "allRecords" -Type "Info"
        return $allRecords
    } catch {
        Write-Message "アプリデータ取得 失敗: $($_.Exception.Message)" -VarName "message" -Type "Error" -ForegroundColor Red
        throw
    }
}


function Set-ResultCellColor {
    param (
        [Parameter(Mandatory)]
        $ResultRange
    )
    $fc = $ResultRange.FormatConditions
    $fc.Delete()

    $addr = $ResultRange.Cells(1,1).Address($false,$false)

    $c1 = $fc.Add(
        [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
        $null,
        "=OR($addr=TRUE,$addr=""提出済"")"
    )
    $c1.Font.Color = 32768
    
    $c2 = $fc.Add(
        [Microsoft.Office.Interop.Excel.XlFormatConditionType]::xlExpression,
        $null,
        "=OR($addr=FALSE,$addr=""未提出"")"
    )
    $c2.Font.Color = 255
    
}

function Scroll-ToOffset {
    param(
        [Parameter(Mandatory=$true)]
        $Sheet,
        [int]$ColOffset = 2,   # 横スクロールの最後列からのオフセット
        [int]$RowOffset = -1    # 縦スクロールの最後行からのオフセット
    )
    $usedRange = $Sheet.UsedRange
    $window = $Sheet.Application.ActiveWindow
    
    # 横スクロール
    if ($ColOffset -ge 0) {
        $lastUsedCol = $usedRange.Column + $usedRange.Columns.Count - 1
        $targetCol = [Math]::Max(1, $lastUsedCol - $ColOffset)
        $window.ScrollColumn = $targetCol
    }
    
    # 縦スクロール
    if ($RowOffset -ge 0) {
        $lastUsedRow = $usedRange.Row + $usedRange.Rows.Count - 1
        $targetRow = if ($RowOffset -eq 0) { $lastUsedRow } else { [Math]::Max(1, $lastUsedRow - $RowOffset) }
        $window.ScrollRow = $targetRow
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
    # 横スクロール
    if ($ColumnIndex -gt 0) {
        $window.ScrollColumn = $ColumnIndex
    }
    # 縦スクロール
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
    # Excel 定数
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
    # Write-Host "row=$($cell.Row) column=$($cell.Column)"
    return $cell
}

function Write-BodyDatas {
    param(
        $StartCell,
        $Datas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    if (-not $Datas) {
        return
    }
    # 1行配列対応
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
        # Excel用2次元配列生成
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
    
    # $range.Borders.LineStyle = 1
}


function Set-SheetTabColor {
    param (
        [Parameter(Mandatory)]
        $Sheet,
        $Error
    )
    if ($Error) {
        $Sheet.Tab.Color = 255  # 赤
    } else {
        $Sheet.Tab.Color = 32768  # 緑
    }
}

function Set-FreezePane {
    param(
        [Parameter(Mandatory)]
        $Sheet,

        [Parameter(Mandatory)]
        [int]$SplitColumn,

        [Parameter(Mandatory)]
        [int]$SplitRow
    )
    $Sheet.Activate()
    $window = $Sheet.Application.ActiveWindow
    # 既存の固定を解除
    $window.FreezePanes = $false
    $window.SplitColumn = 0
    $window.SplitRow = 0
    # 新しく設定
    $window.SplitColumn = $SplitColumn
    $window.SplitRow = $SplitRow
    $window.FreezePanes = $true
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


function Check-HasErrorData {
    param(
        [Parameter(Mandatory)]$Object,
        [string[]]$TargetPropertyNames = $null,  # null → 全プロパティ
        [string]$ResultPropertyName = "result",
        [string]$OkValue = "同じ"
    )

    # 対象となるプロパティ名を決定
    $targetNames =
        if ($TargetPropertyNames -and $TargetPropertyNames.Count -gt 0) {
            $TargetPropertyNames
        }
        else {
            $Object.PSObject.Properties.Name
        }
    
    foreach ($name in $targetNames) {
        # プロパティが存在しなければスキップ
        if (-not $Object.PSObject.Properties.Match($name)) {
            continue
        }
        $value = $Object.$name
        if ($null -eq $value) {
            continue
        }
        # result を持つオブジェクトのみ対象
        if (-not $value.PSObject.Properties.Match($ResultPropertyName)) {
            continue
        }
        if ($value.$ResultPropertyName -ne $OkValue) {
            return $true
        }
    }
    return $false
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

function Set-SheetVisibleModeByKeyword {
    param(
        [Parameter(Mandatory)]
        [object]$Workbook,
        [Parameter(Mandatory)]
        [string]$Keyword,
        [bool]$Visible
    )
    foreach ($sheet in $Workbook.Worksheets) {
        if ($sheet.Name -like "*$Keyword*") {
            if ($Visible) {
                $sheet.Visible = -1   # 表示
            } else {
                $sheet.Visible = 0    # 非表示
            }
        }
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


function Move-SheetsToFront {
    param(
        [object]$Workbook,
        [string]$Keyword
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $targetSheets = @()
    foreach ($sheet in $Workbook.Worksheets) {
        if ($sheet.Name -like "$Keyword*") {
            $targetSheets += $sheet
        }
    }
    $index = 1
    foreach ($sheet in $targetSheets) {
        $sheet.Move($Workbook.Worksheets.Item($index))
        $index++
    }
}


function Get-ColumnDefs {
    param(
        [Parameter(Mandatory)]
        [string[]]$SourceColumns
    )

    $columnDefs = foreach ($s in $SourceColumns) {
        # ハットをエスケープ
        $s = $s -replace '\^', ''
        # パイプで分割
        $parts = $s -split '\|'

        # 列Indexが数値かチェック
        if (-not ($parts[0] -as [int])) {
            throw "列Indexが数値ではありません: $s"
        }

        # オブジェクト作成
        [PSCustomObject]@{
            Index = [int]$parts[0]
            Alias = if ($parts.Count -eq 2 -and $parts[1]) { $parts[1] } else { $null }
            Type = if ($parts.Count -eq 3 -and $parts[2]) { $parts[2] } else { $null }
        }
    }
    return $columnDefs
}

function Export-RangeToFile {
    param(
        [Parameter(Mandatory)]
        $Range,
        [Parameter(Mandatory)]
        [string]$OutputFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $values = $Range.Value2
    
    # 1セルだけの場合は 2次元配列にラップ
    if ($values -isnot [System.Array]) {
        $values = @(@($values.ToString()))
    }
    $rows = $values.GetLength(0)
    $cols = $values.GetLength(1)
    $lines = for ($r = 1; $r -le $rows; $r++) {
        $row = for ($c = 1; $c -le $cols; $c++) {
            $v = $values[$r, $c]
            # 日付変換: Excelのシリアル値 → yyyy/MM/dd
            if ($v -is [double] -and $Range.Cells.Item($r, $c).NumberFormat -match "yy") {
                $v = [datetime]::FromOADate($v).ToString("yyyy/MM/dd")
            }
            if ($null -eq $v) { "" } else { $v }
        }
        $row -join "`t"
    }
    $content = $lines -join "`r`n"
    $dir = Split-Path $OutputFilePath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $content | Set-Content -Path $OutputFilePath
    Write-Message $OutputFilePath -VarName "OutputFilePath" -Type "Info"
}


function Export-ArrayToFile {
    param(
        [Parameter(Mandatory)]
        [array]$Datas,
        [Parameter(Mandatory)]
        [string]$OutputFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    $Datas = Convert-BreakLine $Datas
    $lines = foreach ($row in $Datas) {
        if ($row -isnot [array]) {
            $row = @($row)
        }
        ($row | ForEach-Object {
            if ($null -eq $_) { "" } else { $_ }
        }) -join "`t"
    }
    $content = $lines -join "`r`n"
    $dir = Split-Path $OutputFilePath -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    Set-Content -Path $OutputFilePath -Value $content
    Write-Message $OutputFilePath -VarName "OutputFilePath" -Type "Info"
}



function Read-FileToArray {
    param(
        [Parameter(Mandatory)]
        [string]$ReadFilePath
    )
    $lines = Get-Content -Path $ReadFilePath
    if ($lines.Count -lt 2) { return @() }
    $result = @()
    for ($r = 0; $r -lt $lines.Count; $r++) {
        $values = $lines[$r] -split "`t"
        $values = Restore-BreakLine $values
        $result += ,$values
    }
    return ,$result
}

function Use-Mutex {
    param(
        [string]$Name = "Global",
        [scriptblock]$Action
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $mutex = [System.Threading.Mutex]::new($false, "Global\$Name")
    try {
        $mutex.WaitOne() | Out-Null
        & $Action
    }
    finally {
        $mutex.ReleaseMutex()
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
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
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
    
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
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


function Transpose-Array {
    param(
        [object[][]]$data
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $rowCount = $data.Count
    $colCount = $data[0].Count
    $result = @()
    for ($c = 0; $c -lt $colCount; $c++) {
        $newRow = @()
        for ($r = 0; $r -lt $rowCount; $r++) {
            $newRow += $data[$r][$c]
        }
        $result += ,$newRow
    }
    return $result
}

function Create-CourseDatas {
    param(
        [array]$DataLines
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $courses = @()
    $headerMap = @{
        '科目番号'   = 'courseNo'
        '科目名'     = 'courseName'
        '開始日'     = 'startDate'
        '終了日'     = 'endDate'
    }
    $headers = $DataLines[0] -split ',' | ForEach-Object { $_.Trim() }
    $bodyLines = $DataLines | Select-Object -Skip 1
    foreach ($line in $bodyLines) {
        $parts = $line -split ',' | ForEach-Object { $_.Trim() }
        $course = [PSCustomObject]@{}
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $header = $headers[$i]
            $value  = $parts[$i]
            $course | Add-Member -NotePropertyName $header -NotePropertyValue $value
            if ($headerMap.ContainsKey($header)) {
                $internalName = $headerMap[$header]
                $course | Add-Member -NotePropertyName $internalName -NotePropertyValue $value -Force
            }
        }
        $courses += $course
    }
    return $courses
}


function Create-UserDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $dataLines = Convert-ExcelToCsvString -ExcelFilePath $DataFilePath -SheetIndex 1
    
    $bodies = @()
    $headerMap = @{
        '通番'     = 'userNo'
        '受講生ID' = 'userCode'
        '氏名'     = 'userName'
        '会社名'   = 'companyName'
        'クラス名'  = 'className'
    }
    $headers = $dataLines[0] -split ',' | ForEach-Object { $_.Trim() }
    $bodyLines = $dataLines | Select-Object -Skip 1
    foreach ($line in $bodyLines) {
        $parts = $line -split ',' | ForEach-Object { $_.Trim() }
        $body = [PSCustomObject]@{}
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $header = $headers[$i]
            $value  = $parts[$i]
            $body | Add-Member -NotePropertyName $header -NotePropertyValue $value
            if ($headerMap.ContainsKey($header)) {
                $internalName = $headerMap[$header]
                $body | Add-Member -NotePropertyName $internalName -NotePropertyValue $value
            }
        }
        $unUsable = ToBool $body.停止中
        if ($unUsable) {
            continue
        }
        $bodies += $body
    }
    return $bodies
}

function Create-CourseScheduleDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath,
        [string]$CurrentDate
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $courseLines = Convert-ExcelToCsvString -ExcelFilePath $DataFilePath -SheetIndex -1 -DateColumnIndexes @(3,4)
    $courseDatas = Create-CourseDatas $courseLines
    
    $results = @()
    
    # 開始日
    $firstStart = ($courseDatas | Sort-Object {[datetime]$_.startDate})[0].startDate
    $startDate = [datetime]$firstStart
    
    # 終了日
    $lastEnd = ($courseDatas | Sort-Object {[datetime]$_.endDate} -Descending)[0].endDate
    $endDate = [datetime]$lastEnd
    
    $previousWasHoliday = $false
    
    # 科目ごとの総登場日数を事前計算
    $courseTotalDays = @{}
    for ($date = $startDate; $date -le $endDate; $date = $date.AddDays(1)) {
        $courseForDate = $courseDatas | Where-Object {
            $start = [datetime]$_.startDate
            $end   = [datetime]$_.endDate
            $date -ge $start -and $date -le $end
        }
        foreach ($name in ($courseForDate.courseName | Select-Object -Unique)) {
            if (-not $courseTotalDays.ContainsKey($name)) {
                $courseTotalDays[$name] = 0
            }
            $courseTotalDays[$name]++
        }
    }
    # 連番管理
    $courseCounters = @{}
    for ($date = $startDate; $date -le $endDate; $date = $date.AddDays(1)) {
        $courseForDate = $courseDatas | Where-Object {
            $start = [datetime]$_.startDate
            $end   = [datetime]$_.endDate
            $date -ge $start -and $date -le $end
        }
        if ($courseForDate) {
            $todayCourses = $courseForDate.courseName | Select-Object -Unique
            $displayNames = @()
            foreach ($courseName in $todayCourses) {
                if (-not $courseCounters.ContainsKey($courseName)) {
                    $courseCounters[$courseName] = 0
                }
                $courseCounters[$courseName]++
                # 総登場日数が1日なら連番なし
                if ($courseTotalDays[$courseName] -eq 1) {
                    $displayNames += $courseName
                }
                else {
                    $displayNames += "$courseName（$($courseCounters[$courseName])）"
                }
            }
            $results += [PSCustomObject]@{
                科目名            = ($displayNames -join "/")
                courseName        = ($displayNames -join "/")
                日付              = $date.ToString("yyyy-MM-dd")
                date              = $date.ToString("yyyy-MM-dd")
                isHoliday         = $false
                isHolidayNextDay  = $previousWasHoliday
            }
            $previousWasHoliday = $false
        }
        else {
            # 休日
            $results += [PSCustomObject]@{
                科目名            = "研修無し"
                courseName        = "研修無し"
                日付              = $date.ToString("yyyy-MM-dd")
                date              = $date.ToString("yyyy-MM-dd")
                isHoliday         = $true
                isHolidayNextDay  = $false
            }
            $previousWasHoliday = $true
        }
    }
    if ($CurrentDate) {
        $cutoff = [datetime]::ParseExact($CurrentDate, "yyyy-MM-dd", $null)
        $results = $results | Where-Object {
            [datetime]$_.date -le $cutoff
        }
    }
    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
}

