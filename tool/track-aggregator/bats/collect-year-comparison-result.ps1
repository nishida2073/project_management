param(
    [string]$ClientDataRootDir,
    [string]$TargetGroupName,
    [int]$TargetYear,
    [int]$ComparePeriod,
    [string]$OutputRootDir,
    [string]$TemplateFilePath,
    [string]$SurveyResultRootDir,
    [string]$TestResultRootDir,
    [int]$PassScore,
    [string]$CourseGroupDefs = "",
    [string]$TargetCompanyNames = "",
    [string]$TargetRankNames = "",
    [string]$TargetClassNames = "",
    [int]$YearOrder = 1,
    [string]$OutputFileSuffix = "経年比較結果",
    [string]$LogNamePrefix
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'collect-year-comparison-result' })-$TargetGroupName-$TargetYear"

function Get-YearSummaryDatas {
    param(
        $UserDatas,
        $TestDatas,
        $SurveyDatas,
        [string]$GroupName,
        [array]$Dimensions
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $userCodes = $UserDatas.userCode

    $testResultDatas = Create-TestResultDatas -TestResultRootDir $TestResultRootDir -TargetGroupName $GroupName -TestDatas $TestDatas -PassScore $PassScore
    $validTestResultDatas = $testResultDatas |
        Where-Object { $_.isExecute -and $_.userCode -in $userCodes } |
        Group-Object userCode, testName | ForEach-Object { $_.Group[0] }
    $totalTestSummaryResults = Create-TestSummaryDataByGroup -UserDatas $UserDatas -TestDatas $TestDatas -ValidResultDatas $validTestResultDatas

    $surveyResultDatas = Create-SurveyResultDatas -SurveyResultRootDir $SurveyResultRootDir -TargetGroupName $GroupName -SurveyDatas $SurveyDatas
    $validSurveyResultDatas = $surveyResultDatas |
        Where-Object { $_.isExecute -and $_.userCode -in $userCodes } |
        Group-Object userCode, surveyName | ForEach-Object { $_.Group[0] }
    $totalSurveySummaryResults = Create-SurveySummaryDataByGroup -UserDatas $UserDatas -SurveyDatas $SurveyDatas -ValidResultDatas $validSurveyResultDatas

    $dimensionSummaryResults = [ordered]@{}
    foreach ($dimension in $Dimensions) {
        $dimensionSummaryResults[$dimension.Key] = [PSCustomObject]@{
            testSummaryResults   = Create-TestSummaryDataByGroup -UserDatas $UserDatas -TestDatas $TestDatas -ValidResultDatas $validTestResultDatas -GroupValues $dimension.Names -GroupKey $dimension.Key
            surveySummaryResults = Create-SurveySummaryDataByGroup -UserDatas $UserDatas -SurveyDatas $SurveyDatas -ValidResultDatas $validSurveyResultDatas -GroupValues $dimension.Names -GroupKey $dimension.Key
        }
    }

    return [PSCustomObject]@{
        totalTestSummaryResults   = $totalTestSummaryResults
        totalSurveySummaryResults = $totalSurveySummaryResults
        dimensionSummaryResults   = $dimensionSummaryResults
    }
}


function Get-CourseGroupDatas {
    param(
        [string]$CourseGroupDefs
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta

    $courseGroups = foreach ($groupDef in ($CourseGroupDefs -split ";" | Where-Object { $_ -ne "" })) {
        $parts = $groupDef -split ":", 2
        $groupName = $parts[0]
        $courseNames = if ($parts.Count -gt 1) { @($parts[1] -split "," | Where-Object { $_ -ne "" }) } else { @() }
        [pscustomobject]@{
            groupName   = $groupName
            courseNames = $courseNames
        }
    }
    return @($courseGroups)
}


function Create-YearComparisonDatas {
    param(
        $CourseGroupDatas,
        [array]$YearSummaryDatasList,
        [int]$YearOrder = 1
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $testViewItems = @("平均点", "中央値", "修了率")

    function New-YearRow {
        param($GroupName, $CourseName, $YearLabel, $TestResult, $SurveyResult)
        $row = [ordered]@{
            groupName  = $GroupName
            courseName = $CourseName
            yearLabel  = $YearLabel
        }
        foreach ($testViewItem in $testViewItems) {
            $row[$testViewItem] = if ($TestResult -and $TestResult.isExecute) { $TestResult.$testViewItem } else { $null }
        }
        foreach ($pickedSurveyItem in $pickedSurveyItems) {
            $row[$pickedSurveyItem] = if ($SurveyResult -and $SurveyResult.isExecute) { $SurveyResult.$pickedSurveyItem } else { $null }
        }
        return $row
    }

    $results = foreach ($courseGroup in $CourseGroupDatas) {
        $courseNamesInGroup = if ($courseGroup.courseNames.Count -eq 0) { @($null) } else { $courseGroup.courseNames }
        foreach ($courseName in $courseNamesInGroup) {
            $yearRows = foreach ($yearSummaryDatas in $YearSummaryDatasList) {
                $testResult   = $yearSummaryDatas.summaryDatas.totalTestSummaryResults   | Where-Object { $_.testName -eq $courseName } | Select-Object -First 1
                $surveyResult = $yearSummaryDatas.summaryDatas.totalSurveySummaryResults | Where-Object { $_.surveyName -eq $courseName } | Select-Object -First 1
                New-YearRow -GroupName $courseGroup.groupName -CourseName $courseName -YearLabel "FY$($yearSummaryDatas.year)" -TestResult $testResult -SurveyResult $surveyResult
            }

            $newestRow = $yearRows[0]
            $previousRow = $yearRows[1]
            $diffRow = [ordered]@{
                groupName  = $courseGroup.groupName
                courseName = $courseName
                yearLabel  = "差分"
            }
            foreach ($viewItem in (@($testViewItems) + $pickedSurveyItems)) {
                $currentValue  = $newestRow[$viewItem]
                $previousValue = $previousRow[$viewItem]
                $diffRow[$viewItem] = if ($null -eq $currentValue -and $null -eq $previousValue) {
                    $null
                } else {
                    [double]($currentValue) - [double]($previousValue)
                }
            }

            $displayYearRows = if ($YearOrder -eq 0) { $yearRows[($yearRows.Count - 1)..0] } else { $yearRows }
            foreach ($yearRow in $displayYearRows) { [pscustomobject]$yearRow }
            [pscustomobject]$diffRow
        }
    }
    return $results
}


function Create-DimensionYearComparisonDatas {
    param(
        $CourseGroupDatas,
        [array]$YearSummaryDatasList,
        [string]$DimensionKey,
        [string]$AllLabel,
        [array]$DimensionNames,
        [int]$YearOrder = 1
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $testViewItems = @("平均点", "中央値", "修了率")

    function New-DimensionYearRow {
        param($GroupName, $CourseName, $DimensionKey, $DimensionValue, $YearLabel, $TestResult, $SurveyResult)
        $row = [ordered]@{
            groupName = $GroupName
            courseName = $CourseName
        }
        $row[$DimensionKey] = $DimensionValue
        $row["yearLabel"] = $YearLabel
        foreach ($testViewItem in $testViewItems) {
            $row[$testViewItem] = if ($TestResult -and $TestResult.isExecute) { $TestResult.$testViewItem } else { $null }
        }
        foreach ($pickedSurveyItem in $pickedSurveyItems) {
            $row[$pickedSurveyItem] = if ($SurveyResult -and $SurveyResult.isExecute) { $SurveyResult.$pickedSurveyItem } else { $null }
        }
        return $row
    }

    $results = foreach ($courseGroup in $CourseGroupDatas) {
        $courseNamesInGroup = if ($courseGroup.courseNames.Count -eq 0) { @($null) } else { $courseGroup.courseNames }
        foreach ($courseName in $courseNamesInGroup) {
            $dimensionScopes = @($AllLabel) + $DimensionNames
            foreach ($dimensionValue in $dimensionScopes) {
                $yearRows = foreach ($yearSummaryDatas in $YearSummaryDatasList) {
                    if ($dimensionValue -eq $AllLabel) {
                        $testResult   = $yearSummaryDatas.summaryDatas.totalTestSummaryResults   | Where-Object { $_.testName -eq $courseName } | Select-Object -First 1
                        $surveyResult = $yearSummaryDatas.summaryDatas.totalSurveySummaryResults | Where-Object { $_.surveyName -eq $courseName } | Select-Object -First 1
                    } else {
                        $dimensionSummaryResults = if ($yearSummaryDatas.summaryDatas) { $yearSummaryDatas.summaryDatas.dimensionSummaryResults[$DimensionKey] } else { $null }
                        $testResult   = $dimensionSummaryResults.testSummaryResults   | Where-Object { $_.testName -eq $courseName -and $_.$DimensionKey -eq $dimensionValue } | Select-Object -First 1
                        $surveyResult = $dimensionSummaryResults.surveySummaryResults | Where-Object { $_.surveyName -eq $courseName -and $_.$DimensionKey -eq $dimensionValue } | Select-Object -First 1
                    }
                    New-DimensionYearRow -GroupName $courseGroup.groupName -CourseName $courseName -DimensionKey $DimensionKey -DimensionValue $dimensionValue -YearLabel "FY$($yearSummaryDatas.year)" -TestResult $testResult -SurveyResult $surveyResult
                }

                $newestRow = $yearRows[0]
                $previousRow = $yearRows[1]
                $diffRow = [ordered]@{
                    groupName = $courseGroup.groupName
                    courseName = $courseName
                }
                $diffRow[$DimensionKey] = $dimensionValue
                $diffRow["yearLabel"] = "差分"
                foreach ($viewItem in (@($testViewItems) + $pickedSurveyItems)) {
                    $currentValue  = $newestRow[$viewItem]
                    $previousValue = $previousRow[$viewItem]
                    $diffRow[$viewItem] = if ($null -eq $currentValue -and $null -eq $previousValue) {
                        $null
                    } else {
                        [double]($currentValue) - [double]($previousValue)
                    }
                }

                $displayYearRows = if ($YearOrder -eq 0) { $yearRows[($yearRows.Count - 1)..0] } else { $yearRows }
                foreach ($yearRow in $displayYearRows) { [pscustomobject]$yearRow }
                [pscustomobject]$diffRow
            }
        }
    }
    return $results
}


function Export-GroupedComparisonSheets {
    param($Workbook, [array]$Rows, $TemplateSheetName, [scriptblock]$WriteRows)

    $groupNames = @()
    $rowsByGroup = [ordered]@{}
    foreach ($row in $Rows) {
        if (-not $rowsByGroup.Contains($row.groupName)) {
            $groupNames += $row.groupName
            $rowsByGroup[$row.groupName] = @()
        }
        $rowsByGroup[$row.groupName] += $row
    }

    foreach ($groupName in $groupNames) {
        $sourceSheet = $Workbook.Worksheets.Item($TemplateSheetName)
        $sourceSheet.Copy([Type]::Missing, $Workbook.Sheets.Item($Workbook.Sheets.Count))
        $newSheet = $Workbook.ActiveSheet
        $newSheet.Name = "$TemplateSheetName-$groupName"
        & $WriteRows $newSheet $rowsByGroup[$groupName]
    }

    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)
    & $WriteRows $sheet $Rows
}


function Export-DimensionYearComparisonData {
    param(
        $Workbook,
        $DimensionYearComparisonDatas,
        [int]$RowsPerCourse,
        [int]$DimensionCount,
        [string]$DimensionKey,
        [string]$DimensionHeaderName,
        [string]$SourceTemplateSheetName,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $sourceSheet = $Workbook.Worksheets.Item($SourceTemplateSheetName)
    $sourceSheet.Copy([Type]::Missing, $Workbook.Sheets.Item($Workbook.Sheets.Count))
    $templateSheet = $Workbook.ActiveSheet
    $templateSheet.Name = $TemplateSheetName

    $dimensionNameCell = Get-CellByKey $templateSheet "{属性名}" -ErrorOnMissing
    Write-BodyDatas -StartCell $dimensionNameCell -Datas @($DimensionHeaderName)

    $pickedSurveyItems = Get-PrimeSurveyItems
    $viewItems = @("平均点", "中央値", "修了率") + $pickedSurveyItems

    function Write-DimensionYearComparisonRows {
        param($Sheet, $Rows)

        $dataStartCell = Get-CellByKey $Sheet "{コースグループデータ}" -ErrorOnMissing
        $rowStartIndex = $dataStartCell.Row

        $yearRowCount = $RowsPerCourse - 1
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet 1 -TotalSets $yearRowCount -InsertBeforeCopy

        $rowsPerDimension = $RowsPerCourse
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $rowsPerDimension -TotalSets $DimensionCount

        $rowsPerCourseBlock = $rowsPerDimension * $DimensionCount
        $courseCount = [int]($Rows.Count / $rowsPerCourseBlock)
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $rowsPerCourseBlock -TotalSets $courseCount

        $rowDatas = @()
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $row = $Rows[$i]
            $isFirstRowOfCourse = ($i % $rowsPerCourseBlock -eq 0)
            $isFirstRowOfDimension = ($i % $rowsPerDimension -eq 0)

            $groupCellValue = if ($isFirstRowOfCourse) { $row.groupName } else { "" }
            $courseCellValue = if ($isFirstRowOfCourse) { $row.courseName } else { "" }
            $dimensionCellValue = if ($isFirstRowOfDimension) { $row.$DimensionKey } else { "" }

            $rowData = @("$groupCellValue", "$courseCellValue", "$dimensionCellValue", "$($row.yearLabel)")
            foreach ($viewItem in $viewItems) {
                $value = $row.$viewItem
                if ($viewItem -eq "修了率" -and $null -ne $value -and $value -ne "") {
                    $value = [double]$value / 100
                }
                $rowData += "$value"
            }
            $rowDatas += ,$rowData
        }

        Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex $dataStartCell.Column       -KeySelector { param($r) $r.groupName }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 1) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)" }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 2) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)|$($r.$DimensionKey)" }

        Set-SheetFirstCell -Sheet $Sheet
        Set-AutoFit $Sheet
    }

    Export-GroupedComparisonSheets -Workbook $Workbook -Rows $DimensionYearComparisonDatas -TemplateSheetName $TemplateSheetName -WriteRows ${function:Write-DimensionYearComparisonRows}
}


function Export-YearComparisonData {
    param(
        $Workbook,
        $YearComparisonDatas,
        [int]$RowsPerCourse,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $viewItems = @("平均点", "中央値", "修了率") + $pickedSurveyItems

    function Write-YearComparisonRows {
        param($Sheet, $Rows)

        $dataStartCell = Get-CellByKey $Sheet "{コースグループデータ}" -ErrorOnMissing
        $rowStartIndex = $dataStartCell.Row

        $yearRowCount = $RowsPerCourse - 1
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet 1 -TotalSets $yearRowCount -InsertBeforeCopy

        $courseCount = [int]($Rows.Count / $RowsPerCourse)
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $RowsPerCourse -TotalSets $courseCount

        $rowDatas = @()
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $row = $Rows[$i]
            $isFirstRowOfCourse = ($i % $RowsPerCourse -eq 0)

            $groupCellValue = if ($isFirstRowOfCourse) { $row.groupName } else { "" }
            $courseCellValue = if ($isFirstRowOfCourse) { $row.courseName } else { "" }

            $rowData = @("$groupCellValue", "$courseCellValue", "$($row.yearLabel)")
            foreach ($viewItem in $viewItems) {
                $value = $row.$viewItem
                if ($viewItem -eq "修了率" -and $null -ne $value -and $value -ne "") {
                    $value = [double]$value / 100
                }
                $rowData += "$value"
            }
            $rowDatas += ,$rowData
        }

        Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex $dataStartCell.Column       -KeySelector { param($r) $r.groupName }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 1) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)" }

        Set-SheetFirstCell -Sheet $Sheet
        Set-AutoFit $Sheet
    }

    Export-GroupedComparisonSheets -Workbook $Workbook -Rows $YearComparisonDatas -TemplateSheetName $TemplateSheetName -WriteRows ${function:Write-YearComparisonRows}
}


function Export-Excel {
    param(
        [array]$YearComparisonDatas,
        [array]$DimensionResults,
        [int]$RowsPerCourse,
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

        Export-YearComparisonData -Workbook $workbook -YearComparisonDatas $YearComparisonDatas -RowsPerCourse $RowsPerCourse -TemplateSheetName "経年比較"

        $sourceTemplateSheetName = "経年比較-属性別"
        foreach ($dimensionResult in $DimensionResults) {
            Export-DimensionYearComparisonData -Workbook $workbook -DimensionYearComparisonDatas $dimensionResult.Datas -RowsPerCourse $RowsPerCourse -DimensionCount $dimensionResult.Count -DimensionKey $dimensionResult.Key -SourceTemplateSheetName $sourceTemplateSheetName -DimensionHeaderName $dimensionResult.HeaderName -TemplateSheetName $dimensionResult.SheetName
        }
        $workbook.Worksheets.Item($sourceTemplateSheetName).Delete()

        Set-FirstVisibleSheet -Workbook $workbook
        $workbook.SaveAs($OutputFilePath, 51)
    }
    finally {
        if ($workbook) { $workbook.Close($true) }
        if ($excel) { $excel.Quit() }
        if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    }
}

$psParams = $PSBoundParameters

& {
    $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

    $rowsPerCourse = $ComparePeriod + 2

    New-Item -Path $OutputRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $courseGroupDatas = Get-CourseGroupDatas -CourseGroupDefs $CourseGroupDefs

    $yearDataCache = for ($offset = 0; $offset -le $ComparePeriod; $offset++) {
        $year = $TargetYear - $offset
        $yearMasterFilePath = Join-Path $ClientDataRootDir "$TargetGroupName-$year.xlsx"

        $yearIsExecuted = Test-Path $yearMasterFilePath
        if ($yearIsExecuted) {
            $yearUserDatas = Create-UserDatas -DataFilePath $yearMasterFilePath

            $yearTestDatas = Create-TestDatas -DataFilePath $yearMasterFilePath
            $yearTestDatas = @($yearTestDatas | Where-Object { -not (ToBool $_.停止中) })

            $yearSurveyDatas = Create-SurveyDatas -DataFilePath $yearMasterFilePath
            $yearSurveyDatas = @($yearSurveyDatas | Where-Object { -not (ToBool $_.停止中) })
        } else {
            Write-Message "対象年度のマスタファイルが見つからないため未実施として扱います: $yearMasterFilePath" -VarName "message" -Type "Info" -ForegroundColor Yellow
            $yearUserDatas = $null
            $yearTestDatas = $null
            $yearSurveyDatas = $null
        }

        [PSCustomObject]@{
            year        = $year
            isExecuted  = $yearIsExecuted
            userDatas   = $yearUserDatas
            testDatas   = $yearTestDatas
            surveyDatas = $yearSurveyDatas
        }
    }

    $companyNameFilter = @($TargetCompanyNames -split "," | Where-Object { $_ -ne "" })
    $rankNameFilter = @($TargetRankNames -split "," | Where-Object { $_ -ne "" })
    $classNameFilter = @($TargetClassNames -split "," | Where-Object { $_ -ne "" })

    $allYearsUserDatas = @($yearDataCache.userDatas | Where-Object { $_ })
    $rankOrder = @("S","A","B","C","D","E")
    $companyNames = if ($companyNameFilter.Count -gt 0) { @($companyNameFilter | Select-Object -Unique) } else { @($allYearsUserDatas.companyName | Select-Object -Unique) }
    $rankNames = if ($rankNameFilter.Count -gt 0) { $rankNameFilter } else { $allYearsUserDatas.rankName }
    $rankNames = @($rankNames | Select-Object -Unique | Sort-Object { $rankOrder.IndexOf($_) })
    $classNames = if ($classNameFilter.Count -gt 0) { @($classNameFilter | Sort-Object -Unique) } else { @($allYearsUserDatas.className | Select-Object -Unique | Sort-Object) }

    $dimensionDefs = @(
        [PSCustomObject]@{ Key = "companyName"; AllLabel = "全社";     Names = $companyNames; SheetName = "経年比較-会社別";   HeaderName = "会社名" }
        [PSCustomObject]@{ Key = "className";   AllLabel = "全クラス"; Names = $classNames;   SheetName = "経年比較-クラス別"; HeaderName = "クラス" }
        [PSCustomObject]@{ Key = "rankName";    AllLabel = "全ランク"; Names = $rankNames;    SheetName = "経年比較-ランク別"; HeaderName = "ランク" }
    )

    $yearSummaryDatasList = foreach ($yearData in $yearDataCache) {
        $groupName = "$TargetGroupName-$($yearData.year)"
        $summaryDatas = if ($yearData.isExecuted) {
            Get-YearSummaryDatas -UserDatas $yearData.userDatas -TestDatas $yearData.testDatas -SurveyDatas $yearData.surveyDatas -GroupName $groupName -Dimensions $dimensionDefs
        } else {
            $null
        }

        [PSCustomObject]@{
            year         = $yearData.year
            summaryDatas = $summaryDatas
        }
    }

    $yearComparisonDatas = Create-YearComparisonDatas -CourseGroupDatas $courseGroupDatas -YearSummaryDatasList $yearSummaryDatasList -YearOrder $YearOrder

    $dimensionResults = foreach ($dimensionDef in $dimensionDefs) {
        $dimensionDatas = Create-DimensionYearComparisonDatas -CourseGroupDatas $courseGroupDatas -YearSummaryDatasList $yearSummaryDatasList -DimensionKey $dimensionDef.Key -AllLabel $dimensionDef.AllLabel -DimensionNames $dimensionDef.Names -YearOrder $YearOrder
        [PSCustomObject]@{
            Key        = $dimensionDef.Key
            Datas      = $dimensionDatas
            Count      = $dimensionDef.Names.Count + 1
            SheetName  = $dimensionDef.SheetName
            HeaderName = $dimensionDef.HeaderName
        }
    }

    $outputFilePath = Join-Path $OutputRootDir "$TargetGroupName-$TargetYear-$OutputFileSuffix.xlsx"
    Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force

    Export-Excel -YearComparisonDatas $yearComparisonDatas -DimensionResults $dimensionResults -RowsPerCourse $rowsPerCourse -OutputFilePath $outputFilePath

    Write-MessageComplete "集計結果を出力しました: $outputFilePath"
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-MessageComplete "ログを出力しました: $logFilePath"
