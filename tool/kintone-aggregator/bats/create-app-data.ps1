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

$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'create-app-data' })-$TargetGroupName-$TargetDate"

$appDefinedCodeFields = [PSCustomObject]@{
    DateCodeField                = $TargetDateCodeField
    UserCodeField                = $TargetUserCodeField
}

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
    
    $fieldDatas = if ($TargetAppIds.Count -gt 0) {
        Get-CurrentAppFieldData -TargetAppId $TargetAppIds[0] -BaseUrl $BaseUrl -Authorization $Authorization
    } else {
        $null
    }

    $resultAllDatas = @()
    foreach ($targetAppId in $TargetAppIds) {
        $resultDatas = Get-CurrentAppData -TargetAppId $targetAppId -BaseUrl $BaseUrl -Authorization $Authorization -TargetDateCodeField $appDefinedCodeFields.DateCodeField -TargetDate $TargetDate
        $labelDatas = @()
        foreach ($resultData in $resultDatas) {
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

    $resultAllDatas = @($resultAllDatas | Group-Object userCode |
                          ForEach-Object {
                              $_.Group | Sort-Object { $_.更新日時 } -Descending |
                              Select-Object -First 1
                          })

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
            $rowData += $_.userData.$field
        }
        foreach ($field in $AppCodeFields) {
            $rowData += $_.appData.$field
        }
        $allDatas += ,$rowData
    }
    Export-ArrayToFile $allDatas $OutputFilePath
}

$psParams = $PSBoundParameters

& {
    $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

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
        Write-MessageWarn "対象の科目がありません。日付=$($TargetDate)"
        return
    }
    if($courseScheduleData.isHoliday){
        Write-MessageWarn "休日です。日付=$($TargetDate)"
        return
    }

    $userDatas = Create-UserDatas -DataFilePath $ClientDataFilePath
    Write-Message $userDatas -VarName "userDatas"

    $appDatasResult = Get-AppDatas -TargetAppIds $newTargetAppIds -TargetDate $TargetDate -BaseUrl $BaseUrl -Authorization $Authorization
    $appDatas = $appDatasResult.Datas
    Write-Message $appDatas -VarName "appDatas"

    $appCodeFields = $appDatasResult.AllFieldLabels
    Write-Message $appCodeFields -VarName "appCodeFields"

    $checkResults = Check-Result -AppDatas $appDatas -UserDatas $userDatas -TargetDate $TargetDate -CourseScheduleData $courseScheduleData
    Write-Message $checkResults -VarName "checkResults"

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

    Write-MessageComplete "アプリデータを出力しました: $outputFilePath"
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-MessageComplete "ログを出力しました: $logFilePath"
