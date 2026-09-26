param(
    [string]$BaseUrl,
    [string]$TargetGroupName,
    [string]$KintoneLoginName,
    [string]$KintonePassword,
    [string]$Authorization,
    [string]$AppId,
    [string]$ExcelFilePath,
    [string]$SheetName = "受講生一覧",
    [string]$ConfigPath,
    [string]$LogNamePrefix
)

$script:hasError = $false

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

if (-not $TargetGroupName) {
    $TargetGroupName = [System.IO.Path]::GetFileNameWithoutExtension($ExcelFilePath)
}
$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'sync-kintone-to-sheet' })-$TargetGroupName"

$psParams = $PSBoundParameters

& {
    $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

    if (-not $ConfigPath) {
        Write-MessageError "ConfigPathが指定されていません"
        $script:hasError = $true
        return
    }
    if (-not (Test-Path $ConfigPath)) {
        Write-MessageError "設定ファイルが見つかりません: $ConfigPath"
        $script:hasError = $true
        return
    }
    if (-not $ExcelFilePath) {
        Write-MessageError "ExcelFilePathが指定されていません"
        $script:hasError = $true
        return
    }
    if (-not (Test-Path $ExcelFilePath)) {
        Write-MessageError "Excelファイルが見つかりません: $ExcelFilePath"
        $script:hasError = $true
        return
    }

    $config = Get-Content -Path $ConfigPath -Encoding UTF8 | ConvertFrom-Json
    Write-Message $config -VarName "config" -Type "Info" -ForegroundColor Green

    if ([string]::IsNullOrWhiteSpace($Authorization)) {
        $pair = "${KintoneLoginName}:${KintonePassword}"
        $Authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
    }

    Write-Message "kintoneからデータ取得中..." -Type "Info"
    try {
        $records = Get-AllKintoneRecords -TargetAppId $AppId -BaseUrl $BaseUrl -Authorization $Authorization
    } catch {
        Write-MessageError "kintoneデータ取得エラー: $($_.Exception.Message)"
        $script:hasError = $true
        return
    }

    $recordCount = @($records).Count
    Write-Message "取得レコード数: $recordCount" -Type "Info"
    Write-Message "取得レコード内容:" -Type "Info"
    foreach ($record in $records) {
        $recordData = @()
        foreach ($mapping in $config.columnMappings) {
            if ($mapping.kintoneField) {
                $value = $record.($mapping.kintoneField).value
                $recordData += "$($mapping.sheetColumn)=$value"
            }
        }
        Write-Message "  $($recordData -join ', ')" -Type "Info"
    }

    if (-not $records -or $records.Count -eq 0) {
        Write-MessageError "取得するデータがありません。AppId=$AppId, ExcelFilePath=$ExcelFilePath"
        $script:hasError = $true
        return
    }

    Write-Message "Excel書き込み中..." -Type "Info"
    Use-Mutex "ExcelWriteLock" {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $excel.ScreenUpdating = $false

        try {
            $workbook = $excel.Workbooks.Open($ExcelFilePath)
            $sheet = $workbook.Sheets.Item($SheetName)

            Write-Message "ヘッダ検索中..." -Type "Info"

            $usedRange = $sheet.UsedRange
            $headerColumns = $usedRange.Columns.Count

            $allHeaders = @()
            for ($c = 1; $c -le $headerColumns; $c++) {
                $val = $sheet.Cells.Item(1, $c).Value2
                if ($null -ne $val) {
                    $allHeaders += [string]$val
                }
            }
            Write-Message "読み込まれたヘッダ: $($allHeaders -join ' | ')" -Type "Info"

            $mappingByColumnIndex = @{}

            foreach ($mapping in $config.columnMappings) {
                Write-Message "検索中: $($mapping.sheetColumn)" -Type "Info"
                for ($c = 1; $c -le $headerColumns; $c++) {
                    $headerValue = $sheet.Cells.Item(1, $c).Value2
                    if ($null -eq $headerValue) { continue }
                    $headerStr = [string]$headerValue
                    if ($headerStr -eq $mapping.sheetColumn) {
                        $mappingByColumnIndex[$c] = @{
                            sheetColumn = $mapping.sheetColumn
                            kintoneField = $mapping.kintoneField
                            defaultValue = if ($mapping.defaultValue -ne $null) { $mapping.defaultValue } else { "" }
                            isAutoIncrement = $mapping.defaultValue -eq "increment"
                        }
                        break
                    }
                }
            }

            Write-Message "マッピング完了: $($mappingByColumnIndex.Count) 列" -Type "Info"

            if ($mappingByColumnIndex.Count -eq 0) {
                throw "設定ファイルの列がシートに見つかりません。シートヘッダ: $($allHeaders -join ', ')"
            }


            Write-Message "レコード変換中..." -Type "Info"
            $dataArray = @()
            $rowNum = 1
            foreach ($record in $records) {
                $row = @()
                for ($c = 1; $c -le $headerColumns; $c++) {
                    if ($mappingByColumnIndex.ContainsKey($c)) {
                        $mapping = $mappingByColumnIndex[$c]
                        $defaultValue = $mapping.defaultValue
                        if ($mapping.isAutoIncrement) {
                            $value = $rowNum
                        } elseif ($mapping.kintoneField) {
                            $fieldValue = $record.($mapping.kintoneField)
                            $value = if ($fieldValue -and $fieldValue.value) { $fieldValue.value } else { $defaultValue }
                        } else {
                            $value = $defaultValue
                        }
                        $row += $value
                    } else {
                        $row += ""
                    }
                }
                $dataArray += , $row
                $rowNum++
            }
            Write-Message "2次元配列作成: $($dataArray.Count) 行 x $headerColumns 列" -Type "Info"

            Remove-DataRows -Sheet $sheet -StartRow 2 -StartCol 1

            Write-Message "Excelに書き込み中..." -Type "Info"
            if ($dataArray.Count -gt 0) {
                $startCell = $sheet.Cells.Item(2, 1)
                Write-BodyDatas -StartCell $startCell -Datas $dataArray
            }

            $workbook.Save()
            Write-MessageComplete "Excel書き込み完了: $ExcelFilePath (シート: $SheetName, 行数: $($dataArray.Count))"
        } catch {
            Write-MessageError "Excel操作エラー: $($_.Exception.Message)"
            $script:hasError = $true
            return
        } finally {
            if ($workbook) { $workbook.Close($false); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
            if ($excel) { $excel.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
        }
    }

} *>&1 | Tee-Object -FilePath $logFilePath

ConvertTo-Utf8LogFile -Path $logFilePath
Write-MessageComplete "ログを出力しました: $logFilePath"

if ($script:hasError) { throw "同期処理に失敗しました" }
