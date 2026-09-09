param(
    [string]$BaseUrl,
    [string]$ClientDataFilePath,
    [string]$TargetGroupName,
    [string]$OutputRootDir,
    [string]$TemplateFilePath,
    [string]$SurveyResultRootDir,
    [string]$TestResultRootDir,
    [int]$PassScore,
    [string]$OutputFileSuffix = "統合結果",
    [string]$LogNamePrefix
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'collect-combine-result' })-$TargetGroupName"

function Create-CollectResultsDatas {
    param(
        $UserDatas,
        $SurveyDatas,
        $SurveyResultDatas,
        $TestDatas,
        $ValidTestResultDatas,
        $TotalTestResultsDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
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
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
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
            if ($testResults.平均点 -ne "") {
                $rowData += [double] $testResults.平均点
            } else {
                $rowData += ""
            }
            if ($testResults.中央値 -ne "") {
                $rowData += [double] $testResults.中央値
            } else {
                $rowData += ""
            }
            if ($testResults.修了率 -ne "") {
                $rowData += [double] $testResults.修了率/100
            } else {
                $rowData += ""
            }
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
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)

    # データ取得用のリンク
    # $psRootDir = Split-Path -Parent $MyInvocation.PSCommandPath
    # $downloadFilePath = Join-Path $psRootDir "download-results.bat"
    # $downloadValue = '=HYPERLINK("' + $downloadFilePath + '","データ取得")'
    # $downloadCell = Get-CellByKey $sheet "{データ取得}" -ErrorOnMissing
    # Write-BodyDatas -StartCell $downloadCell -Datas @($downloadValue)
    
    $columnsPerSet = 2 # テスト・アンケートの2列1セット

    # 名称でテストとアンケートを対にした「コース」の一覧（テスト優先の順で並べる）
    $courseNames = [ordered]@{}
    foreach ($testData in $TestDatas) {
        if (-not $courseNames.Contains($testData.testName)) { $courseNames[$testData.testName] = $true }
    }
    foreach ($surveyData in $SurveyDatas) {
        if (-not $courseNames.Contains($surveyData.surveyName)) { $courseNames[$surveyData.surveyName] = $true }
    }
    $courseNameList = @($courseNames.Keys)

    # 実施結果が1件でもあるテスト・アンケート名
    $testCourseNamesWithResult = @($PlainTestResults | Where-Object { $_.testResult } | Select-Object -ExpandProperty testName -Unique)
    $surveyCourseNamesWithResult = @($PlainSurveyResults | Where-Object { $_.surveyResult } | Select-Object -ExpandProperty surveyName -Unique)

    $courseDataCell = Get-CellByKey $sheet "{コースデータ}" -ErrorOnMissing
    $columsStartIndex = $courseDataCell.Column
    # 列のコピー（コースごとに テスト・アンケート の2列セット）
    Expand-ColumnsFromTemplate -Sheet $sheet -TemplateStartColumn $columsStartIndex -TotalSets $courseNameList.Count -ColumnsPerSet $columnsPerSet

    $headData = @()
    foreach ($courseName in $courseNameList) {
        $headData += $courseName
        $headData += [string[]]::new($columnsPerSet - 1)
    }
    $headDatas = ,$headData
    Write-BodyDatas -StartCell $courseDataCell -Datas $headDatas

    $userDataCell = Get-CellByKey $sheet "{ユーザーデータ}" -ErrorOnMissing
    $statusDataCell = Get-CellByKey $sheet "{実施データ}" -ErrorOnMissing

    # ユーザ別
    $userRowDatas = @()
    $statusRowDatas = @()
    foreach ($userData in $UserDatas) {
        $userRowDatas += ,@($userData.userCode, $userData.userName, $userData.companyName, $userData.className, $userData.rankName)

        $userUrl = "$BaseUrl/k/#/people/user/$($userData.userCode)"
        $userTestResults = @($PlainTestResults | Where-Object { $_.userCode -eq $userData.userCode })
        $userSurveyResults = @($PlainSurveyResults | Where-Object { $_.userCode -eq $userData.userCode })

        $statusRow = @()
        foreach ($courseName in $courseNameList) {
            if ($TestDatas.testName -notcontains $courseName) {
                $statusRow += "対象外"
            } elseif ($testCourseNamesWithResult -notcontains $courseName) {
                $statusRow += "データなし"
            } else {
                $testResult = $userTestResults | Where-Object { $_.testName -eq $courseName } | Select-Object -First 1
                if ($testResult -and $testResult.isExecute) {
                    if ($testResult.testResult.isPass) {
                        $statusRow += "実施済み"
                    } else {
                        $statusRow += '=HYPERLINK("' + $userUrl + '","督促（再実施）")'
                    }
                } else {
                    $statusRow += '=HYPERLINK("' + $userUrl + '","督促（未実施）")'
                }
            }

            if ($SurveyDatas.surveyName -notcontains $courseName) {
                $statusRow += "対象外"
            } elseif ($surveyCourseNamesWithResult -notcontains $courseName) {
                $statusRow += "データなし"
            } else {
                $surveyResult = $userSurveyResults | Where-Object { $_.surveyName -eq $courseName } | Select-Object -First 1
                if ($surveyResult -and $surveyResult.isExecute) {
                    $statusRow += "実施済み"
                } else {
                    $statusRow += '=HYPERLINK("' + $userUrl + '","督促（未実施）")'
                }
            }
        }
        $statusRowDatas += ,$statusRow
    }
    if ($userRowDatas.Count -eq 0) {
        $userRowDatas += ,@("")
        $statusRowDatas += ,@("")
    }

    $rowStartIndex = $userDataCell.Row

    # 行のコピー
    Expand-RowsFromTemplate -Sheet $sheet -TemplateStartRow $rowStartIndex -TotalSets $userRowDatas.Count

    # データの書き込み
    Write-BodyDatas -StartCell $userDataCell -Datas $userRowDatas
    Write-BodyDatas -StartCell $statusDataCell -Datas $statusRowDatas

    # 初期セル設定
    Set-SheetFirstCell -Sheet $sheet

    # オートフィルター
    $lastColumnIndex = $statusDataCell.Column + $statusRowDatas[0].Count - 1
    $headerRange = $sheet.Range(
        $sheet.Cells.Item($rowStartIndex - 1, $userDataCell.Column),
        $sheet.Cells.Item($rowStartIndex - 1, $lastColumnIndex)
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
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
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


& {
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

    New-Item -Path $OutputRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $userDatas = Create-UserDatas -DataFilePath $ClientDataFilePath
    # Write-Message $userDatas -VarName "userDatas" -Type "Info"

    $testDatas = Create-TestDatas -DataFilePath $ClientDataFilePath
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

    $surveyDatas = Create-SurveyDatas -DataFilePath $ClientDataFilePath
    $surveyDatas = @($surveyDatas | Where-Object { -not (ToBool $_.停止中) })

    # Write-Message $surveyDatas -VarName "surveyDatas" -Type "Info"

    $surveyResultDatas = Create-SurveyResultDatas -SurveyResultRootDir $SurveyResultRootDir -TargetGroupName $TargetGroupName -SurveyDatas $surveyDatas
    # Write-Message $surveyResultDatas -VarName "surveyResultDatas" -Type "Info"

    $collectResultDatas = Create-CollectResultsDatas -UserDatas $userDatas -SurveyDatas $surveyDatas -SurveyResultDatas $surveyResultDatas -TestDatas $testDatas -ValidTestResultDatas $validTestResultDatas -TotalTestResultsDatas $totalTestResultsDatas
    # Write-Message $collectResultDatas -VarName "collectResultDatas" -Type "Info"

    $outputFilePath = Join-Path $OutputRootDir "$TargetGroupName-$OutputFileSuffix.xlsx"
    Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force

    Export-Excel -CollectResultDatas $collectResultDatas -UserDatas $userDatas -TestDatas $testDatas -SurveyDatas $surveyDatas -OutputFilePath $outputFilePath
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
