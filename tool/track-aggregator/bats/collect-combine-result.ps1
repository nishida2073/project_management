param(
    [string]$BaseUrl,
    [string]$MasterDataFilePath,
    [string]$TargetGroupName,
    [string]$OutputRootDir,
    [string]$TemplateFilePath,
    [string]$SurveyResultRootDir,
    [string]$TestResultRootDir,
    [int]$PassScore
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.psm1 -Recurse | ForEach-Object {
    Import-Module $_.FullName -ErrorAction Stop -DisableNameChecking
}

function Create-CollectResultsDatas {
    param(
        $UserDatas,
        $SurveyDatas,
        $SurveyResultDatas,
        $TestDatas,
        $ValidTestResultDatas,
        $TotalTestResultsDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $userCodes = $UserDatas.userCode
    $validSurveyResultDatas = $SurveyResultDatas |
        Where-Object {
            $_.isExecute -and $_.userCode -in $userCodes
        } |
        Group-Object userCode, surveyName | ForEach-Object { $_.Group[0] }

    $plainSurveyResults = foreach ($userData in $UserDatas) {
        $userResults = @($validSurveyResultDatas | Where-Object { $_.userCode -eq $userData.userCode })
        foreach ($surveyData in $SurveyDatas) {
            $filtered = $userResults | Where-Object { $_.surveyName -eq $surveyData.surveyName }| Select-Object -First 1
            [pscustomobject]@{
                userCode    = $userData.userCode
                userData    = $userData
                surveyName  = $surveyData.surveyName
                surveyResult = $filtered
                isExecute   = $filtered -and $filtered.isExecute
            }
        }
    }

    $plainTestResults = foreach ($userData in $UserDatas) {
        $userResults = @($ValidTestResultDatas | Where-Object { $_.userCode -eq $userData.userCode })
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

    $ClassNames = $UserDatas.className | Sort-Object -Unique
    $CompanyNames = $UserDatas.companyName | Select-Object -Unique
    $rankOrder = @("S","A","B","C","D","E")
    $RankNames = $UserDatas.rankName | Select-Object -Unique | Sort-Object { $rankOrder.IndexOf($_) }

    # totalSummary
    $totalSummarySurveyResults = Create-SurveySummaryDataByGroup `
        -UserDatas $UserDatas `
        -SurveyDatas $SurveyDatas `
        -ValidResultDatas $validSurveyResultDatas

    # combine
    $combineSummaryResults = [ordered]@{}
    foreach ($t in $TotalTestResultsDatas) {
        $key = $t.テスト名
        if (-not $combineSummaryResults.Contains($key)) {
            $combineSummaryResults[$key] = [ordered]@{}
        }
        $combineSummaryResults[$key].Test = $t
    }
    foreach ($s in $totalSummarySurveyResults) {
        $key = $s.surveyName
        if (-not $combineSummaryResults.Contains($key)) {
            $combineSummaryResults[$key] = [ordered]@{}
        }
        $combineSummaryResults[$key].Survey = $s
    }

    # 全体
    $results = [PSCustomObject]@{
        combineSummaryResults  = $combineSummaryResults

        plainSurveyResults = $plainSurveyResults
        plainTestResults = $plainTestResults

        totalSummarySurveyResults = $totalSummarySurveyResults
    }

    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
}


function Export-CombineSummaryData {
    param(
        $Workbook,
        $CombineSummaryResults,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems

    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)

    $rowDatas = @()
    foreach ($key in $CombineSummaryResults.Keys) {
        $testResults   = $CombineSummaryResults[$key].Test
        $surveyResults = $CombineSummaryResults[$key].Survey
        $rowData = @()
        $rowData +=  $key
        if( $testResults ){
            $rowData +=  if($testResults.平均点 -ne "") { [double] $testResults.平均点 }
            $rowData +=  if($testResults.中央値 -ne "") { [double] $testResults.中央値 }
            $rowData +=  if($testResults.修了率 -ne "") { [double] $testResults.修了率/100 }
        } else {
            $rowData += @("") * 3
        }
        if( $surveyResults ){
            foreach ($pickedSurveyItem in $pickedSurveyItems) {
                $exists = $surveyResults | Where-Object { $_.PSObject.Properties[$pickedSurveyItem] }
                if ($exists) {
                    $rowData += $surveyResults.$pickedSurveyItem
                }else{
                    $rowData +=""
                }
            }
        } else {
            $rowData += @("") * $pickedSurveyItems.Count
        }
        $rowDatas += ,$rowData
    }

    $dataStartCell = Get-CellByKey $sheet "{結果データ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    # 行のコピー
    Expand-RowsFromTemplate -Sheet $sheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count
    # データの書き込み
    Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

    # 初期セル設定
    Set-SheetFirstCell -Sheet $sheet

}


function Export-ExecutionStatusData {
    param(
        $Workbook,
        $UserDatas,
        $TestDatas,
        $SurveyDatas,
        $PlainTestResults,
        $PlainSurveyResults,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)

    # 名称でテストとアンケートを対にして並べる（同名なら テスト列→アンケート列 の順で隣接させる）
    $itemNames = [ordered]@{}
    foreach ($testData in $TestDatas) {
        if (-not $itemNames.Contains($testData.testName)) { $itemNames[$testData.testName] = $true }
    }
    foreach ($surveyData in $SurveyDatas) {
        if (-not $itemNames.Contains($surveyData.surveyName)) { $itemNames[$surveyData.surveyName] = $true }
    }
    $columnSpecs = @()
    foreach ($itemName in $itemNames.Keys) {
        if ($TestDatas.testName -contains $itemName) {
            $columnSpecs += [pscustomobject]@{ Type = "Test"; Name = $itemName }
        }
        if ($SurveyDatas.surveyName -contains $itemName) {
            $columnSpecs += [pscustomobject]@{ Type = "Survey"; Name = $itemName }
        }
    }

    $dataStartCell = Get-CellByKey $sheet "{実施データ}" -ErrorOnMissing
    $columsStartIndex = $dataStartCell.Column
    # 列のコピー
    Expand-ColumnsFromTemplate -Sheet $sheet -TemplateStartColumn $columsStartIndex -TotalSets $columnSpecs.Count -ColumnsPerSet 1

    $headData = @()
    foreach ($columnSpec in $columnSpecs) {
        if ($columnSpec.Type -eq "Test") {
            $headData += "$($columnSpec.Name)（テスト）"
        } else {
            $headData += "$($columnSpec.Name)（アンケート）"
        }
    }
    $headDatas = ,$headData
    Write-BodyDatas -StartCell $dataStartCell -Datas $headDatas

    # ユーザ別
    $rowDatas = @()
    foreach ($userData in $UserDatas) {
        $rowData = @()
        $rowData += $userData.userCode
        $rowData += $userData.userName
        $rowData += $userData.companyName
        $rowData += $userData.className
        $rowData += $userData.rankName

        $userUrl = "$BaseUrl/k/#/people/user/$($userData.userCode)"

        $userTestResults = @($PlainTestResults | Where-Object { $_.userCode -eq $userData.userCode })
        $userSurveyResults = @($PlainSurveyResults | Where-Object { $_.userCode -eq $userData.userCode })

        foreach ($columnSpec in $columnSpecs) {
            if ($columnSpec.Type -eq "Test") {
                $result = $userTestResults | Where-Object { $_.testName -eq $columnSpec.Name } | Select-Object -First 1
                if ($result -and $result.isExecute) {
                    if ($result.testResult.isPass) {
                        $rowData += "実施済み"
                    } else {
                        $rowData += '=HYPERLINK("' + $userUrl + '","督促（不合格）")'
                    }
                } else {
                    $rowData += '=HYPERLINK("' + $userUrl + '","督促（未実施）")'
                }
            } else {
                $result = $userSurveyResults | Where-Object { $_.surveyName -eq $columnSpec.Name } | Select-Object -First 1
                if ($result -and $result.isExecute) {
                    $rowData += "実施済み"
                } else {
                    $rowData += '=HYPERLINK("' + $userUrl + '","督促（未実施）")'
                }
            }
        }
        $rowDatas += ,$rowData
    }
    if ($rowDatas.Count -eq 0) {
        $rowDatas += ,@("")
    }

    $dataStartCell = Get-CellByKey $sheet "{ユーザーデータ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column

    # 行のコピー
    Expand-RowsFromTemplate -Sheet $sheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count

    # データの書き込み
    Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

    # 初期セル設定
    Set-SheetFirstCell -Sheet $sheet

    # オートフィルター
    $headerRange = $sheet.Range(
        $sheet.Cells.Item($rowStartIndex - 1, $columsStartIndex),
        $sheet.Cells.Item($rowStartIndex - 1, $columsStartIndex + $rowDatas[0].Count - 1)
    )
    Set-AutoFilter $headerRange

    # オートフィット
    Set-AutoFit $sheet
}


function Export-Excel {
    param(
        [object]$CollectResultDatas,
        [array]$UserDatas,
        [array]$TestDatas,
        [array]$SurveyDatas,
        [string]$OutputFilePath
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

        Export-CombineSummaryData -Workbook $workbook -CombineSummaryResults $CollectResultDatas.combineSummaryResults -TemplateSheetName "サマリ"

        Export-ExecutionStatusData -Workbook $workbook -UserDatas $UserDatas -TestDatas $TestDatas -SurveyDatas $SurveyDatas -PlainTestResults $CollectResultDatas.plainTestResults -PlainSurveyResults $CollectResultDatas.plainSurveyResults -TemplateSheetName "実施状況"

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

$userDatas = Create-UserDatas -DataFilePath $MasterDataFilePath
# Write-Message $userDatas -VarName "userDatas" -Type "Info"

$testDatas = Create-TestDatas -DataFilePath $MasterDataFilePath
$testDatas = @($testDatas | Where-Object { -not (ToBool $_.停止中) })
# Write-Message $testDatas -VarName "testDatas" -Type "Info"

$testResultDatas = Create-TestResultDatas -TestResultRootDir $TestResultRootDir -TargetGroupName $TargetGroupName -TestDatas $testDatas -PassScore $PassScore
# Write-Message $testResultDatas -VarName "testResultDatas" -Type "Info"

$testUserCodes = $userDatas.userCode
$validTestResultDatas = $testResultDatas |
    Where-Object {
        $_.isExecute -and $_.userCode -in $testUserCodes
    } |
    Group-Object userCode, testName | ForEach-Object { $_.Group[0] }

$totalTestResultsDatas = Create-TestSummaryDataByGroup -UserDatas $userDatas -TestDatas $testDatas -ValidResultDatas $validTestResultDatas
# Write-Message $totalTestResultsDatas -VarName "totalTestResultsDatas" -Type "Info"

$surveyDatas = Create-SurveyDatas -DataFilePath $MasterDataFilePath
$surveyDatas = @($surveyDatas | Where-Object { -not (ToBool $_.停止中) })

# Write-Message $surveyDatas -VarName "surveyDatas" -Type "Info"

$surveyResultDatas = Create-SurveyResultDatas -SurveyResultRootDir $SurveyResultRootDir -TargetGroupName $TargetGroupName -SurveyDatas $surveyDatas
# Write-Message $surveyResultDatas -VarName "surveyResultDatas" -Type "Info"

$collectResultDatas = Create-CollectResultsDatas -UserDatas $userDatas -SurveyDatas $surveyDatas -SurveyResultDatas $surveyResultDatas -TestDatas $testDatas -ValidTestResultDatas $validTestResultDatas -TotalTestResultsDatas $totalTestResultsDatas
# Write-Message $collectResultDatas -VarName "collectResultDatas" -Type "Info"

$outputFilePath = Join-Path $OutputRootDir "$TargetGroupName-統合結果.xlsx"
Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force

Export-Excel -CollectResultDatas $collectResultDatas -UserDatas $userDatas -TestDatas $testDatas -SurveyDatas $surveyDatas -OutputFilePath $outputFilePath
