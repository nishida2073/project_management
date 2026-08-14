param(
    [string]$BaseUrl,
    [string]$MasterDataFilePath,
    [string]$TargetGroupName,
    [string]$OutputRootDir,
    [string]$ResultRootDir,
    [string]$TemplateFilePath,
    [int]$PassScore,
    [int]$ShowDetail
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.psm1 -Recurse | ForEach-Object {
    Import-Module $_.FullName -ErrorAction Stop -DisableNameChecking
}

function Create-CollectResultsDatas {
    param(
        $UserDatas,
        $TestDatas,
        $ResultDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $ClassNames = $UserDatas.className | Sort-Object -Unique
    $CompanyNames = $UserDatas.companyName | Select-Object -Unique
    $rankOrder = @("S","A","B","C","D","E")
    $RankNames = $UserDatas.rankName | Select-Object -Unique | Sort-Object { $rankOrder.IndexOf($_) }
    
    $userCodes = $UserDatas.userCode
    
    $validResultDatas = $ResultDatas |
        Where-Object {
            $_.isExecute -and $_.userCode -in $userCodes
        } |
        Group-Object userCode, testName | ForEach-Object { $_.Group[0] }
    
    # plain
    $plainResults = foreach ($userData in $UserDatas) {
        $userResults = @($validResultDatas | Where-Object { $_.userCode -eq $userData.userCode })
        foreach ($testData in $TestDatas) {
            $filtered = $userResults | Where-Object { $_.testName -eq $testData.testName }| Select-Object -First 1
            [pscustomobject]@{
                userCode    = $userData.userCode
                userData    = $userData
                testName    = $testData.testName
                testResult  = $filtered
                isExecute   = $filtered -and $filtered.isExecute
            }
        }
    }
    
    # totalSummary
    $totalSummaryResults = Create-TestSummaryDataByGroup `
        -UserDatas $UserDatas `
        -TestDatas $TestDatas `
        -ValidResultDatas $validResultDatas
    
    # companySummary
    $companySummaryResults = Create-TestSummaryDataByGroup `
        -GroupValues $CompanyNames `
        -GroupKey "companyName" `
        -UserDatas $UserDatas `
        -TestDatas $TestDatas `
        -ValidResultDatas $validResultDatas
    
    # classSummary
    $classSummaryResults = Create-TestSummaryDataByGroup `
        -GroupValues $ClassNames `
        -GroupKey "className" `
        -UserDatas $UserDatas `
        -TestDatas $TestDatas `
        -ValidResultDatas $validResultDatas
    
    # rankSummary
    $rankSummaryResults = Create-TestSummaryDataByGroup `
        -GroupValues $RankNames `
        -GroupKey "rankName" `
        -UserDatas $UserDatas `
        -TestDatas $TestDatas `
        -ValidResultDatas $validResultDatas
    
    $results = [PSCustomObject]@{
        plainResults          = $plainResults
        totalSummaryResults   = $totalSummaryResults
        companySummaryResults = $companySummaryResults
        classSummaryResults   = $classSummaryResults
        rankSummaryResults    = $rankSummaryResults
    }
    # Write-Message $results.totalSummaryResults -VarName "totalSummaryResults" -Type "Info"
    # Write-Message $results.companySummaryResults -VarName "results" -Type "Info"
    return $results
}



function Export-UserSummaryData {
    param(
        $Workbook,
        $TestDatas,
        $TotalSummaryResults,
        $PlainResults,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)
    
    $dataStartCell = Get-CellByKey $sheet "{テストデータ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column
    Expand-ColumnsFromTemplate -Sheet $sheet -TemplateStartColumn $columsStartIndex -TotalSets $TestDatas.Count
    
    $headData = @()
    foreach ($testData in $TestDatas) {
        $headData += $testData.testName
    }
    $headDatas = ,$headData
    Write-BodyDatas -StartCell $dataStartCell -Datas $headDatas
    
    $rowDatas = @()
    
    # 全体
    $totalViewItems = @("平均点")
    foreach ($totalViewItem in $totalViewItems) {
        $rowData = @()
        $rowData += @("全体-$totalViewItem","-","-","-","-")
        foreach ($testData in $TestDatas) {
            $totalResult = $TotalSummaryResults | Where-Object { $_.testName -eq $testData.testName } |
                          Select-Object -First 1
            if ($totalResult){
                $rowData += "$($totalResult.$totalViewItem)"
            } else {
                $rowData += ""
            }
        }
        $rowDatas += ,$rowData
    }
    
    # ユーザー別
    $uniqueUsers = @($PlainResults |
        Group-Object -Property { $_.userData.userCode } |
        ForEach-Object { 
            $first = $_.Group[0].userData
            [PSCustomObject]@{
                userCode    = $first.userCode
                userName    = $first.userName
                companyName = $first.companyName
                className   = $first.className
                rankName    = $first.rankName
            }
        })
    foreach ($uniqueUser in $uniqueUsers) {
        $rowData = @()
        
        $rowData += $uniqueUser.userCode
        $rowData += $uniqueUser.userName
        $rowData += $uniqueUser.companyName
        $rowData += $uniqueUser.className
        $rowData += $uniqueUser.rankName
        
        $userTestResults = $PlainResults | Where-Object { $_.userData.userCode -eq $uniqueUser.userCode }
        
        foreach ($testData in $TestDatas) {
            $testResult = $userTestResults | Where-Object { $_.testName -eq $testData.testName } | Select-Object -First 1 -ExpandProperty testResult
            
            if ($testResult.isExecute){
                $rowData += $testResult.score
            } else {
                $rowData += ""
            }
        }
        $rowDatas += ,$rowData
    }
    
    # Write-Message $rowDatas -VarName "rowDatas" -Type "Info" -ForegroundColor Green
    
    $dataStartCell = Get-CellByKey $sheet "{ユーザーデータ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column
    # 行のコピー
    Expand-RowsFromTemplate -Sheet $sheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count
    
    # データの書き込み
    Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas
    
    # 初期セル設定
    Set-SheetFirstCell -Sheet $sheet
    
    # オートフィット
    Set-AutoFit $sheet
    
    # オートフィルター
    $headerRange = $sheet.Range(
        $sheet.Cells.Item($rowStartIndex - 1, $columsStartIndex),
        $sheet.Cells.Item($rowStartIndex - 1, $columsStartIndex + $rowDatas[0].Count - 1)
    )
    Set-AutoFilter $headerRange
    
    # セルの色
    $resultRange = $sheet.Range(
        $Sheet.Cells.Item($rowStartIndex + $totalViewItems.Count, $columsStartIndex + 6 -1 ), 
        $Sheet.Cells.Item($rowStartIndex + $rowDatas.Count - 1,  $columsStartIndex + $rowDatas[0].Count -1 ))
    Set-ResultCellColorByThreshold $resultRange $PassScore

}


function Export-GroupSummaryData {
    param(
        $Workbook,
        $TestDatas,
        $TotalSummaryResults,
        $UseSummaryResults,
        $TemplateSheetName,
        $TargetUniquePropName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $viewItems = @("予定数","実施数","合格数","不合格数","平均点","中央値","修了率","最高点","最低点")
    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)

    $result = Export-GroupSummaryDataCore `
        -Sheet $sheet `
        -DataItems $TestDatas `
        -ItemNameProperty "testName" `
        -ViewItems $viewItems `
        -TotalResults $TotalSummaryResults `
        -UseSummaryResults $UseSummaryResults `
        -TargetUniquePropName $TargetUniquePropName `
        -DataMarkerKey "{テストデータ}" `
        -FormatAsText

    # セルの色
    $rowStartIndex = $result.RowStartIndex
    $columsStartIndex = $result.ColumnStartIndex
    $rowDatas = $result.RowDatas
    $lastRowIndex = $rowStartIndex + $rowDatas.Count - 1
    $resultRange = $sheet.Range(
        $sheet.Cells($rowStartIndex + 1, $columsStartIndex + 1),
        $sheet.Cells($lastRowIndex, $columsStartIndex + $rowDatas[0].Count - 1)
    )
    Set-CompareTotalCellColor -ResultRange $resultRange -TotalRowIndex $rowStartIndex -BlockSize 9 -SkipInBlock 4
}


function Export-UserPlainData {
    param(
        $Workbook,
        $TestDatas,
        $TotalSummaryResults,
        $PlainResults,
        $TemplateSheetName,
        $ShowDetail
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    $newSheetNameParts = $TemplateSheetName -split "-", 2
    $newSheetNameFormat = "$($newSheetNameParts[0])-{0}-$($newSheetNameParts[1])"
        
    if( $ShowDetail ){
        foreach ($testData in $TestDatas) {
            $sourceSheet = $Workbook.Worksheets.Item($TemplateSheetName)
            $sourceSheet.Copy([Type]::Missing, $Workbook.Sheets.Item($Workbook.Sheets.Count))
            $newSheet = $Workbook.ActiveSheet
            $newSheet.Name = $newSheetNameFormat -f $testData.testName
            
            $targetPlainResults = @($PlainResults | Where-Object { $_.testName -eq $testData.testName })
            $targetTotalSummaryResult = $TotalSummaryResults | Where-Object { $_.testName -eq $testData.testName } | Select-Object -First 1
            $questionCount = if($targetTotalSummaryResult){ [int]$targetTotalSummaryResult.questionCount } else { 0 }

            $rowDatas = @()
            $rowData = @()
            for ($i = 1; $i -le $questionCount; $i++) {
                $rowData += "問題$i"
            }
            if($questionCount -eq 0){
                $rowData += ""
            }
            $rowDatas +=,$rowData

            $dataStartCell = Get-CellByKey $newSheet "{問題データ}" -ErrorOnMissing
            $rowStartIndex = $dataStartCell.Row
            $columsStartIndex = $dataStartCell.Column
            # 列のコピー
            Expand-ColumnsFromTemplate -Sheet $newSheet -TemplateStartColumn $columsStartIndex -TotalSets $rowDatas[0].Count
            # データの書き込み
            Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

            $rowDatas = @()
            # 合計
            $rowData = @()
            $rowData += "正答率"
            $rowData += ""
            $rowData += ""
            $rowData += ""
            $rowData += ""
            $rowData += ""

            for ($i = 1; $i -le $questionCount; $i++) {
                $propName = "Q$i"
                $propValues = $targetTotalSummaryResult.$propName
                $rowData += "$propValues%"
            }
            $rowDatas += ,$rowData
            
            # ユーザ別
            foreach ($targetPlainResult in $targetPlainResults) {
                $targetUserData = $targetPlainResult.userData
                $rowData = @()
                $rowData += $targetUserData.userCode
                $rowData += $targetUserData.userName
                $rowData += $targetUserData.companyName
                $rowData += $targetUserData.className
                $rowData += $targetUserData.rankName
                if ($targetPlainResult.isExecute){
                    $rowData += ""
                } else {
                    $userUrl = "$BaseUrl/k/#/people/user/$($targetUserData.userCode)"
                    $rowData += '=HYPERLINK("' + $userUrl + '","督促")'
                }
                $targetResult = $targetPlainResult.testResult
                for ($i = 1; $i -le $questionCount; $i++) {
                    $propName = "Q$i"
                    $propValue = $targetResult.$propName
                    if ($targetPlainResult.isExecute) {
                        $rowData += if( $propValue -eq 1 ){ "〇" } else { "×" }
                    } else {
                        $rowData += ""
                    }
                }
                $rowDatas += ,$rowData
            }
            if($rowDatas.Count -eq 0){
                $rowDatas += ,@("")
            }
            
            $dataStartCell = Get-CellByKey $newSheet "{ユーザーデータ}" -ErrorOnMissing
            $rowStartIndex = $dataStartCell.Row
            $columsStartIndex = $dataStartCell.Column
            
            # 行のコピー
            Expand-RowsFromTemplate -Sheet $newSheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count
            
            # データの書き込み
            Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas
            
            # 初期セル設定
            Set-SheetFirstCell -Sheet $newSheet
            
            # オートフィルター
            $headerRange = $newSheet.Range(
                $newSheet.Cells.Item($rowStartIndex - 1,$columsStartIndex),
                $newSheet.Cells.Item($rowStartIndex - 1,$columsStartIndex + $rowDatas[0].Count - 1)
            )
            Set-AutoFilter $headerRange
            
            # セルの色
            $resultRange = $newSheet.Range(
                $newSheet.Cells.Item($rowStartIndex + 1, $columsStartIndex + $rowDatas[0].Count - $questionCount), 
                $newSheet.Cells.Item($rowStartIndex + $rowDatas.Count - 1,  $columsStartIndex + $rowDatas[0].Count -1 ))
            Set-ResultCellColorByWord $resultRange "〇"
            
            # オートフィット
            Set-AutoFit $newSheet
        }
    }
    Remove-Sheet $Workbook $TemplateSheetName
}


function Export-GroupPlainData {
    param(
        $Workbook,
        $TestDatas,
        $TotalSummaryResults,
        $UseSummaryResults,
        $TemplateSheetName,
        $TargetUniquePropName,
        $ShowDetail
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    if( $ShowDetail ){
        $newSheetNameParts = $TemplateSheetName -split "-", 2
        $newSheetNameFormat = "$($newSheetNameParts[0])-{0}-$($newSheetNameParts[1])"
        
        foreach ($testData in $TestDatas) {
            $sourceSheet = $Workbook.Worksheets.Item($TemplateSheetName)
            $sourceSheet.Copy([Type]::Missing, $Workbook.Sheets.Item($Workbook.Sheets.Count))
            $newSheet = $Workbook.ActiveSheet
            $newSheet.Name = $newSheetNameFormat -f $testData.testName
            
            $targetUseSummaryResults = @($UseSummaryResults | Where-Object { $_.testName -eq $testData.testName })
            $targetTotalSummaryResult = $TotalSummaryResults | Where-Object { $_.testName -eq $testData.testName } | Select-Object -First 1
            $questionCount = if($targetTotalSummaryResult){ [int]$targetTotalSummaryResult.questionCount } else { 0 }

            $rowDatas = @()
            $rowData = @()
            for ($i = 1; $i -le $questionCount; $i++) {
                $rowData += "問題$i"
            }
            if($questionCount -eq 0){
                $rowData += ""
            }
            $rowDatas +=,$rowData

            $dataStartCell = Get-CellByKey $newSheet "{問題データ}" -ErrorOnMissing
            $rowStartIndex = $dataStartCell.Row
            $columsStartIndex = $dataStartCell.Column
            # 列のコピー
            Expand-ColumnsFromTemplate -Sheet $newSheet -TemplateStartColumn $columsStartIndex -TotalSets $rowDatas[0].Count
            # データの書き込み
            Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

            $rowDatas = @()
            # 全体
            $rowData = @()
            $rowData += "全体"

            for ($i = 1; $i -le $questionCount; $i++) {
                $propName = "Q$i"
                $propValue = $targetTotalSummaryResult.$propName
                $rowData += "$propValue%"
            }
            $rowDatas += ,$rowData
            
            # X別
            foreach ($targetUseSummaryResult in $targetUseSummaryResults) {
                $rowData = @()
                $rowData += "$($targetUseSummaryResult.$TargetUniquePropName)"
                for ($i = 1; $i -le $questionCount; $i++) {
                    $propName = "Q$i"
                    $propValue = $targetUseSummaryResult.$propName
                    $rowData += "$propValue%"
                }
                $rowDatas += ,$rowData
            }
            if($rowDatas.Count -eq 0){
                $rowDatas += ,@("")
            }
            
            $dataStartCell = Get-CellByKey $newSheet "{結果データ}" -ErrorOnMissing
            $rowStartIndex = $dataStartCell.Row
            $columsStartIndex = $dataStartCell.Column
            
            # 行のコピー
            Expand-RowsFromTemplate -Sheet $newSheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count
            
            # データの書き込み
            Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas
            
            # 初期セル設定
            Set-SheetFirstCell -Sheet $newSheet
            
            # オートフィルター
            $headerRange = $newSheet.Range(
                $newSheet.Cells.Item($rowStartIndex - 1,$columsStartIndex),
                $newSheet.Cells.Item($rowStartIndex - 1,$columsStartIndex + $rowDatas[0].Count - 1)
            )
            Set-AutoFilter $headerRange
            
            # オートフィット
            Set-AutoFit $newSheet
        }
    }
    Remove-Sheet $Workbook $TemplateSheetName
}


function Export-Excel {
    param(
        [array]$TestDatas,
        [PSObject]$CollectResultDatas,
        [string]$OutputFilePath,
        [string]$TemplateFilePath,
        [bool]$ShowDetail
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $excel = $null
    $workbook = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $excel.ScreenUpdating = $false
        $excel.EnableEvents = $false
        
        $workbook = $excel.Workbooks.Open($OutputFilePath)
        
        # データ作成
        Export-UserSummaryData -Workbook $workbook -TestDatas $TestDatas -TotalSummaryResults $CollectResultDatas.totalSummaryResults -PlainResults $CollectResultDatas.plainResults -TemplateSheetName "サマリ-ユーザー別"
        
        Export-GroupSummaryData -Workbook $workbook -TestDatas $TestDatas -TotalSummaryResults $CollectResultDatas.totalSummaryResults -UseSummaryResults $CollectResultDatas.classSummaryResults -TemplateSheetName "サマリ-クラス別" -TargetUniquePropName "className"
        
        Export-GroupSummaryData -Workbook $workbook -TestDatas $TestDatas -TotalSummaryResults $CollectResultDatas.totalSummaryResults -UseSummaryResults $CollectResultDatas.companySummaryResults -TemplateSheetName "サマリ-会社別" -TargetUniquePropName "companyName"
        
        Export-GroupSummaryData -Workbook $workbook -TestDatas $TestDatas -TotalSummaryResults $CollectResultDatas.totalSummaryResults -UseSummaryResults $CollectResultDatas.rankSummaryResults -TemplateSheetName "サマリ-ランク別" -TargetUniquePropName "rankName"
        
        Export-UserPlainData -Workbook $workbook -TestDatas $TestDatas -TotalSummaryResults $CollectResultDatas.totalSummaryResults -PlainResults $CollectResultDatas.plainResults -TemplateSheetName "詳細-ユーザ別" -ShowDetail $ShowDetail
        
        Export-GroupPlainData -Workbook $workbook -TestDatas $TestDatas -TotalSummaryResults $CollectResultDatas.totalSummaryResults -UseSummaryResults $CollectResultDatas.classSummaryResults -TemplateSheetName "詳細-クラス別" -TargetUniquePropName "className" -ShowDetail $ShowDetail
        
        Export-GroupPlainData -Workbook $workbook -TestDatas $TestDatas -TotalSummaryResults $CollectResultDatas.totalSummaryResults -UseSummaryResults $CollectResultDatas.companySummaryResults -TemplateSheetName "詳細-会社別" -TargetUniquePropName "companyName" -ShowDetail $ShowDetail
        
        Export-GroupPlainData -Workbook $workbook -TestDatas $TestDatas -TotalSummaryResults $CollectResultDatas.totalSummaryResults -UseSummaryResults $CollectResultDatas.rankSummaryResults -TemplateSheetName "詳細-ランク別" -TargetUniquePropName "rankName" -ShowDetail $ShowDetail
        
        # 最初のシートをアクティブに
        Set-FirstVisibleSheet -Workbook $workbook
        
        # 保存
        $workbook.SaveAs($OutputFilePath, 51)
    }
    finally {
        if ($workbook) { $workbook.Close($true) }
        if ($excel) { $excel.Quit() }
        if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    }
}


New-Item -Path $OutputRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$showDetail = if($ShowDetail -eq 1){ $true } else { $false }

$testDatas = Create-TestDatas -DataFilePath $MasterDataFilePath
$testDatas = @($testDatas | Where-Object { -not (ToBool $_.停止中) })
# Write-Message $testDatas -VarName "testDatas" -Type "Info"

$userDatas = Create-UserDatas -DataFilePath $MasterDataFilePath
# Write-Message $userDatas -VarName "userDatas" -Type "Info"

$resultDatas = Create-TestResultDatas -TestResultRootDir $ResultRootDir -TargetGroupName $TargetGroupName -TestDatas $testDatas -PassScore $PassScore
# Write-Message $resultDatas -VarName "resultDatas" -Type "Info"

$collectResultDatas = Create-CollectResultsDatas -UserDatas $userDatas -TestDatas $testDatas -ResultDatas $resultDatas
# Write-Message $collectResultDatas -VarName "collectResultDatas" -Type "Info"

$outputFilePath = Join-Path $OutputRootDir "$TargetGroupName-テスト結果.xlsx"
Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force
Export-Excel -TestDatas $testDatas -CollectResultDatas $collectResultDatas -TemplateFilePath $TemplateFilePath -OutputFilePath $outputFilePath -ShowDetail $showDetail

