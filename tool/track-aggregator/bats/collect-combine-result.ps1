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

$primeSurveyItems = @("S27","S1","S2","S7","S10","S13","S16","S19","S22","S25")

function Create-SurveyDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $headerMap = @{
        '通番'   = 'surveyNo'
        'アンケート名'     = 'surveyName'
    }
    return Create-MasterDatas -DataFilePath $DataFilePath -SheetIndex 3 -HeaderMap $headerMap
}


function Create-ResultDatas {
    param(
        [string]$SurveyResultRootDir,
        [string]$TargetGroupName,
        [array]$SurveyDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $allResultDatas = @()
    foreach($surveyData in $SurveyDatas){
        $surveyName = $surveyData.surveyName
        $surveyGroupDir = Join-Path $SurveyResultRootDir $TargetGroupName
        $surveyResultDir = Join-Path $surveyGroupDir $surveyName
        $resultFiles = @(Get-ChildItem $surveyResultDir -Filter *.csv)
        foreach($resultFile in $resultFiles){
            $csv = Import-Csv $resultFile.FullName
            foreach ($row in $csv) {
                $obj = $row | Select-Object *
                $obj | Add-Member -NotePropertyName surveyName -NotePropertyValue $surveyName
                $obj | Add-Member -NotePropertyName userCode -NotePropertyValue $row.account
                $obj | Add-Member -NotePropertyName isExecute -NotePropertyValue ($row.status -ne "NotStarted")
                $surveyCount = ($obj.PSObject.Properties.Name -like 'surveyAnswerValue*').Count
                $obj | Add-Member -NotePropertyName surveyCount -NotePropertyValue $surveyCount
                for ($i = 0; $i -lt $obj.surveyCount; $i++) {
                    $propName = "surveyAnswerValue/$i"
                    $propValue = if ($obj.PSObject.Properties.Name -contains $propName){
                        $obj.$propName
                    }else {
                        ""
                    }
                    $obj | Add-Member -NotePropertyName "S$i" -NotePropertyValue $propValue
                }
                $allResultDatas += $obj
            }
        }
    }
    # Write-Message $allResultDatas -VarName "allResultDatas" -Type "Info"
    return $allResultDatas
}


function Create-TestDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $headerMap = @{
        '通番'   = 'testNo'
        'テスト名'     = 'testName'
    }
    return Create-MasterDatas -DataFilePath $DataFilePath -SheetIndex 2 -HeaderMap $headerMap
}


function Create-TestResultDatas {
    param(
        [string]$TestResultRootDir,
        [string]$TargetGroupName,
        [array]$TestDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $allResultDatas = @()
    foreach($testData in $TestDatas){
        $testName = $testData.testName
        $testGroupDir = Join-Path $TestResultRootDir $TargetGroupName
        $testResultDir = Join-Path $testGroupDir $testName
        $resultFiles = @(Get-ChildItem $testResultDir -Filter *.csv)
        foreach($resultFile in $resultFiles){
            $csv = Import-Csv $resultFile.FullName
            foreach ($row in $csv) {
                $obj = $row | Select-Object *
                $obj | Add-Member -NotePropertyName testName -NotePropertyValue $testName
                $obj | Add-Member -NotePropertyName userCode -NotePropertyValue $row.account
                $obj | Add-Member -NotePropertyName isExecute -NotePropertyValue ($row.status -ne "NotStarted")
                if (-not ($obj.PSObject.Properties.Name -contains 'score')) {
                    $challengeSuccessfulTestcases = [int]$row.challengeSuccessfulTestcases
                    $challengeTotalTestcases = [int]$row.challengeTotalTestcases
                    $score = if ($challengeTotalTestcases -ne 0) {
                        ($challengeSuccessfulTestcases / $challengeTotalTestcases) * 100
                    } else {
                        ""
                    }
                    $obj | Add-Member -NotePropertyName score -NotePropertyValue $score
                }
                if (-not ($obj.PSObject.Properties.Name -contains 'questionCount')) {
                    $challengeTotalTestcases = [int]$row.challengeTotalTestcases
                    $obj | Add-Member -NotePropertyName questionCount -NotePropertyValue $challengeTotalTestcases
                }
                for ($i = 1; $i -le $obj.questionCount; $i++) {
                    $propName = "q$i/score"
                    $propValue = if ($obj.PSObject.Properties.Name -contains $propName){
                        $obj.$propName
                    }else {
                        ""
                    }
                    $obj | Add-Member -NotePropertyName "Q$i" -NotePropertyValue $propValue
                }
                $obj | Add-Member -NotePropertyName isPass -NotePropertyValue ([int]$obj.score -ge $PassScore)
                $allResultDatas += $obj
            }
        }
    }
    # Write-Message $allResultDatas -VarName "allResultDatas" -Type "Info" -ForegroundColor Green
    return $allResultDatas
}


function Get-TestMedian {
    param(
        [array]$values
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green

    $sorted = $values |
        Where-Object { $_ -ne $null -and $_ -ne "" } |
        ForEach-Object { [double]$_ } |
        Sort-Object
    $count = $sorted.Count
    if ($count -eq 0) { return $null }
    $mid = [math]::Floor($count / 2)

    $median = if ($count % 2 -eq 1) {
        $sorted[$mid]
    }
    else {
        ($sorted[$mid - 1] + $sorted[$mid]) / 2
    }

    return $median
}


function Create-TestSummaryDataByGroup {
    param(
        [array]$ValidResultDatas,
        [array]$UserDatas,
        [array]$TestDatas,
        [array]$GroupValues,
        [string]$GroupKey
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $results = foreach ($group in (Get-GroupedResults -UserDatas $UserDatas -ValidResultDatas $ValidResultDatas -GroupValues $GroupValues -GroupKey $GroupKey)) {
        $groupUsers = $group.GroupUsers
        $groupResults = $group.GroupResults
        foreach ($testData in $TestDatas) {
            $filtered = @(
                $groupResults |
                Where-Object { $_.testName -eq $testData.testName }
            )
            $planCount   = $groupUsers.Count
            $actualCount = $filtered.Count
            $passedCount = @($filtered | Where-Object isPass).Count
            if ($actualCount -eq 0) {
                $passedPercentage = 0
            } else {
                $passedPercentage = ($passedCount / $actualCount) * 100
            }
            $scores = $filtered.score | ForEach-Object { [int]$_ }
            $stats  = $scores | Measure-Object -Average -Maximum -Minimum
            $isExecute = ($filtered.Count -ne 0)

            $obj = [ordered]@{}
            if ($GroupKey) {
                $obj[$GroupKey] = $group.GroupValue
            }
            $obj += @{
                テスト名  = $testData.testName
                testName  = $testData.testName
                isExecute = $isExecute
                scores    = if ($isExecute) { $scores } else { "" }
                予定数    = $planCount
                実施数    = $actualCount
                合格数    = if ($isExecute) { $passedCount } else { "" }
                不合格数  = if ($isExecute) { $actualCount - $passedCount } else { "" }
                修了率    = if ($isExecute) { $passedPercentage } else { "" }
                平均点    = if ($isExecute) { $stats.Average } else { "" }
                中央値    = if ($isExecute) { Get-TestMedian $scores } else { "" }
                最高点    = if ($isExecute) { $stats.Maximum } else { "" }
                最低点    = if ($isExecute) { $stats.Minimum } else { "" }
            }

            # 設問正答率
            if ($isExecute) {
                $questionCount = [int]$filtered[0].questionCount
                $obj["questionCount"] = $questionCount
                for ($i = 1; $i -le $questionCount; $i++) {
                    $propName = "Q$i"
                    $propValues = $filtered | Where-Object { $_.isExecute -and $_.PSObject.Properties.Name -contains $propName } | ForEach-Object { $_.$propName }
                    $avgValue = ($propValues | Measure-Object -Average).Average
                    if ($null -eq $avgValue) {
                        $avgValue = 0
                    } else {
                        $avgValue = [int]($avgValue * 100)
                    }
                    $obj["Q$i"] = $avgValue
                }
            }
            [pscustomobject]$obj
        }
    }
    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
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
    $totalSummarySurveyResults = Create-SummaryDataByGroup `
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


function Create-SummaryDataByGroup {
    param(
        [array]$ValidResultDatas,
        [array]$UserDatas,
        [array]$SurveyDatas,
        [array]$GroupValues,
        [string]$GroupKey
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $results = foreach ($group in (Get-GroupedResults -UserDatas $UserDatas -ValidResultDatas $ValidResultDatas -GroupValues $GroupValues -GroupKey $GroupKey)) {
        $groupUsers = $group.GroupUsers
        $groupResults = $group.GroupResults
        foreach ($surveyData in $SurveyDatas) {
            $filtered = @(
                $groupResults |
                Where-Object { $_.surveyName -eq $surveyData.surveyName }
            )
            $planCount   = $groupUsers.Count
            $actualCount = $filtered.Count
            $isExecute = ($filtered.Count -ne 0)
            $obj = [ordered]@{}
            # total 以外のみグループキー追加
            if ($GroupKey) {
                $obj[$GroupKey] = $group.GroupValue
            }
            $obj += @{
                surveyName  = $surveyData.surveyName
                isExecute = $isExecute
                planCount    = $planCount
                actualCount  = $actualCount
            }

            # 平均
            if ($isExecute) {
                $surveyCount = [int]$filtered[0].surveyCount
                $obj["surveyCount"] = $surveyCount
                foreach ($primeSurveyItem in $primeSurveyItems) {
                    $propValues = $filtered | Where-Object { $_.isExecute -and $_.PSObject.Properties.Name -contains $primeSurveyItem } | ForEach-Object { $_.$primeSurveyItem }
                    $avgValue = ($propValues | Measure-Object -Average).Average
                    if ($null -eq $avgValue) {
                        $avgValue = ""
                    }
                    $obj[$primeSurveyItem] = $avgValue
                }
            }
            [pscustomobject]$obj
        }
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

    $pickedSurveyItems = $primeSurveyItems

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

$testResultDatas = Create-TestResultDatas -TestResultRootDir $TestResultRootDir -TargetGroupName $TargetGroupName -TestDatas $testDatas
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

$surveyResultDatas = Create-ResultDatas -SurveyResultRootDir $SurveyResultRootDir -TargetGroupName $TargetGroupName -SurveyDatas $surveyDatas
# Write-Message $surveyResultDatas -VarName "surveyResultDatas" -Type "Info"

$collectResultDatas = Create-CollectResultsDatas -UserDatas $userDatas -SurveyDatas $surveyDatas -SurveyResultDatas $surveyResultDatas -TestDatas $testDatas -ValidTestResultDatas $validTestResultDatas -TotalTestResultsDatas $totalTestResultsDatas
# Write-Message $collectResultDatas -VarName "collectResultDatas" -Type "Info"

$outputFilePath = Join-Path $OutputRootDir "$TargetGroupName-統合結果.xlsx"
Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force

Export-Excel -CollectResultDatas $collectResultDatas -UserDatas $userDatas -TestDatas $testDatas -SurveyDatas $surveyDatas -OutputFilePath $outputFilePath
