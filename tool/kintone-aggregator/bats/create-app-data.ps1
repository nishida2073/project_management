param(
    [string]$BaseUrl,
    [string]$ClientDataFilePath,
    [string]$TargetGroupName,
    [string]$KintoneLoginName,
    [string]$KintonePassword,
    [string]$Authorization,
    [string]$OutputRootDir,
    [string]$OutputFileNameSuffix,
    [int]$CreateReminderLink,
    [string]$TargetAppIds,
    [string]$TargetDate,
    [string]$TargetDateCodeField,
    [string]$TargetUserCodeField,
    [string]$LogNamePrefix
)
$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

# create-daily-report.bat/create-pulse-survey.batの両方がこのps1を共有しているため、
# ログファイル名で呼び出し元を区別できるよう呼び出し元の.bat名をLogNamePrefixとして受け取る
$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'create-app-data' })-$TargetGroupName-$TargetDate"

$appDefinedCodeFields = [PSCustomObject]@{
    DateCodeField                = $TargetDateCodeField
    UserCodeField                = $TargetUserCodeField
}

# TargetAppIds用のパース処理。カンマ・空白区切りの文字列を空要素を除いた配列にする
function Get-FieldCodeList {
    param(
        [string]$Value
    )
    return @($Value -split '[,\s]+' | Where-Object { $_ })
}


function Get-AppDatas {
    param(
        [array]$TargetAppIds,
        [string]$TargetDate,
        [string]$BaseUrl,
        [string]$Authorization
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    # アプリの構造（フィールドコード・ラベル）はレコードの有無に関わらず取得できる、
    # レコード取得（Get-CurrentAppData）とは別のAPIのため、ループの外で独立して取得する。
    # 対象日のレコードが1件も無いと、以前はレコードのループが回らず$fieldDatasが
    # 一度も取得されない（＝集計対象フィールドが展開できない）不具合があった
    $fieldDatas = if ($TargetAppIds.Count -gt 0) {
        Get-CurrentAppFieldData -TargetAppId $TargetAppIds[0] -BaseUrl $BaseUrl -Authorization $Authorization
    } else {
        $null
    }

    $resultAllDatas = @()
    foreach ($targetAppId in $TargetAppIds) {
        # 結果取得
        $resultDatas = Get-CurrentAppData -TargetAppId $targetAppId -BaseUrl $BaseUrl -Authorization $Authorization -TargetDateCodeField $appDefinedCodeFields.DateCodeField -TargetDate $TargetDate
        $labelDatas = @()
        foreach ($resultData in $resultDatas) {
            # フィールドをラベルに変換
            $labelData = [PSCustomObject]@{}
            foreach ($fieldCode in $resultData.PSObject.Properties.Name) {
                if ($null -ne $fieldDatas.PSObject.Properties[$fieldCode]) {
                    $label = $fieldDatas.$fieldCode.label
                    Add-Member -InputObject $labelData -MemberType NoteProperty -Name $label -Value $resultData.$fieldCode.value -Force
                } 
                Add-Member -InputObject $labelData -MemberType NoteProperty -Name $fieldCode -Value $resultData.$fieldCode.value -Force
            }
            $userCode = Get-NestedPropertyValue -Object $labelData -PropertyPath $appDefinedCodeFields.UserCodeField
            Add-Member -InputObject $labelData -MemberType NoteProperty -Name userCode -Value $userCode -Force
            $labelDatas += $labelData
        }
        $resultAllDatas += $labelDatas
    }
    Write-Message $resultAllDatas -VarName "resultAllDatas"

    # 最新版を取得
    $resultAllDatas = @($resultAllDatas | Group-Object userCode |
                          ForEach-Object {
                              $_.Group | Sort-Object { $_.更新日時 } -Descending |
                              Select-Object -First 1
                          })

    # 集計対象フィールド（AllFieldLabels）の算出用。アプリの全フィールドのラベル名から、
    # 日付・受講生ID特定に既に使っているフィールド（DateCodeField/UserCodeField）を除いたもの。
    # UserCodeFieldは"作成者.code"のようなネストパス（kintoneのCREATOR等サブテーブル系フィールド）
    # を指定できるため、比較は最初の"."より前のベースのフィールドコードで行う
    $excludeFieldCodes = @(
        $appDefinedCodeFields.DateCodeField
        ($appDefinedCodeFields.UserCodeField -split '\.')[0]
    )
    $allFieldLabels = if ($fieldDatas) {
        @($fieldDatas.PSObject.Properties.Name |
            Where-Object { $excludeFieldCodes -notcontains $_ } |
            ForEach-Object { $fieldDatas.$_.label } |
            Where-Object { $_ })
    } else {
        @()
    }

    return [PSCustomObject]@{
        Datas          = $resultAllDatas
        AllFieldLabels = $allFieldLabels
    }
}


function Check-Result {
    param(
        [array]$AppDatas,
        [array]$UserDatas,
        [string]$TargetDate,
        [object]$CourseScheduleData
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $checkResults = @()
    foreach ($userData in $UserDatas) {
        $appData = $AppDatas | Where-Object { $_.userCode -eq $userData.userCode } | Select-Object -First 1
        if ($appData) {
            $existStatus = $true
        } else {
            $existStatus = $false
        }
        $userData | Add-Member -MemberType NoteProperty -Name "scheduledDate" -Value $TargetDate -Force
        $userData | Add-Member -MemberType NoteProperty -Name "日付" -Value $TargetDate -Force
        if( $CourseScheduleData ){
            $courseName = $CourseScheduleData.courseName
        } else {
            $courseName = ""
        }
        $userData | Add-Member -MemberType NoteProperty -Name "isHoliday" -Value $CourseScheduleData.isHoliday -Force
        $userData | Add-Member -MemberType NoteProperty -Name "scheduledCourseName" -Value $courseName -Force
        $userData | Add-Member -MemberType NoteProperty -Name "科目名" -Value $courseName -Force
        if( $CreateReminderLink -eq 1){
            $userUrl = "$BaseUrl/k/#/people/user/$($userData.userCode)"
            $reminderLink = '=HYPERLINK("' + $userUrl + '","督促")'
        }else {
            $reminderLink = ""
        }
        $checkResults += [PSCustomObject]@{
            userData    = $userData
            appData     = $appData
            existStatus = $existStatus
            reminderLink = $reminderLink
        }
    }
    return $checkResults
}


function Export-File {
    param(
        [array]$CheckResults,
        [string]$OutputFilePath,
        [array]$FixedCodeFields,
        [array]$AppCodeFields
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $allDatas = @()
    $rowData = @("提出状況")
    foreach ($field in $FixedCodeFields) {
        $rowData += $field
    }
    foreach ($field in $AppCodeFields) {
        $rowData += $field
    }
    $allDatas +=,$rowData

    $CheckResults | ForEach-Object {
        $rowData = @($_.existStatus)

        foreach ($field in $FixedCodeFields) {
            # Write-Message "field = $field"
            $rowData += $_.userData.$field
        }
        foreach ($field in $AppCodeFields) {
            $rowData += $_.appData.$field
        }
        $allDatas += ,$rowData
    }
    Export-ArrayToFile $allDatas $OutputFilePath
}



& {
    $newTargetAppIds = Get-FieldCodeList -Value $TargetAppIds

    New-Item -Path $OutputRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    if ([string]::IsNullOrWhiteSpace($Authorization)) {
        $pair = "${KintoneLoginName}:${KintonePassword}"
        $Authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
    }


    $courseScheduleDatas = Create-CourseScheduleDatas -DataFilePath $ClientDataFilePath -CurrentDate $TargetDate
    Write-Message $courseScheduleDatas -VarName "courseScheduleDatas"

    $courseScheduleData = $CourseScheduleDatas | Where-Object { $_.date -eq $TargetDate } | Select-Object -First 1
    Write-Message $courseScheduleData -VarName "courseScheduleData"

    if(-not $courseScheduleData){
        Write-Message "対象の科目がありません。日付=$($TargetDate)" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        return
    }
    if($courseScheduleData.isHoliday){
        Write-Message "休日です。日付=$($TargetDate)" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        return
    }

    $userDatas = Create-UserDatas -DataFilePath $ClientDataFilePath
    Write-Message $userDatas -VarName "userDatas"

    $appDatasResult = Get-AppDatas -TargetAppIds $newTargetAppIds -TargetDate $TargetDate -BaseUrl $BaseUrl -Authorization $Authorization
    $appDatas = $appDatasResult.Datas
    Write-Message $appDatas -VarName "appDatas"

    # kintoneアプリの全フィールド（ラベル名）のうち、日付・受講生ID特定に使用済みの
    # フィールドを除いた残り全部を集計対象にする
    $appCodeFields = $appDatasResult.AllFieldLabels
    Write-Message $appCodeFields -VarName "appCodeFields"

    $checkResults = Check-Result -AppDatas $appDatas -UserDatas $userDatas -TargetDate $TargetDate -CourseScheduleData $courseScheduleData
    Write-Message $checkResults -VarName "checkResults"

    # userData（受講生データにCheck-Resultが科目名・日付等を付与した後の最終形）の全プロパティのうち、
    # Create-UserDatas/Check-Resultが別名として付与した英語エイリアス（userNo/userCode/userName/
    # companyName/className/scheduledDate/isHoliday/scheduledCourseName）を除いた残り全部を
    # 固定列にする。userDataのプロパティ一覧はCheck-Result実行後でないと日付・科目名を含んだ
    # 最終形にならないため、ここで算出する
    $userDataAliasFieldCodes = @(
        "userNo", "userCode", "userName", "companyName", "className",
        "scheduledDate", "isHoliday", "scheduledCourseName"
    )
    $fixedCodeFields = if ($checkResults.Count -gt 0) {
        @($checkResults[0].userData.PSObject.Properties.Name |
            Where-Object { $userDataAliasFieldCodes -notcontains $_ })
    } else {
        @()
    }
    Write-Message $fixedCodeFields -VarName "fixedCodeFields"

    $outputFileName = "$TargetGroupName-$($OutputFileNameSuffix.TrimStart('_')).txt"
    $outputFilePath = Join-Path $OutputRootDir $outputFileName
    Export-File -CheckResults $checkResults -OutputFilePath $outputFilePath -FixedCodeFields $fixedCodeFields -AppCodeFields $appCodeFields
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
