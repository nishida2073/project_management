# =========================================
# テンプレートと新スペースのダウンロード結果からconfigを自動生成する
# =========================================

param(
    [string]$LogNamePrefix,
    [string]$BaseTemplateConfigName,
    [string]$CustomTemplateConfigName,
    [string]$DownloadConfigName,
    [string]$TargetGroupName,
    [string]$BaseTemplateRoot,
    [string]$CustomTemplateRoot,
    [string]$ConfigRoot,
    [string]$DownloadRoot,
    [string]$LogRoot,
    [ValidateSet("Template", "Download")][string]$PreferredDataSource = "Template"
)

$libraryDir = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

function Get-PreferredValue {
    param($CustomValue, $BaseValue)
    if ("$CustomValue" -ne "") { return $CustomValue }
    return $BaseValue
}

function Merge-KintoneRowsByKey {
    param(
        [array]$BaseRows,
        [array]$CustomRows,
        [string[]]$KeyProperties
    )
    $result = New-Object System.Collections.Generic.List[psobject]
    $indexByKey = @{}
    foreach ($row in @($BaseRows)) {
        if ($null -eq $row) { continue }
        $key = ($KeyProperties | ForEach-Object { "$($row.$_)" }) -join "`u{0}"
        $indexByKey[$key] = $result.Count
        $result.Add($row)
    }
    foreach ($row in @($CustomRows)) {
        if ($null -eq $row) { continue }
        $key = ($KeyProperties | ForEach-Object { "$($row.$_)" }) -join "`u{0}"
        if ($indexByKey.ContainsKey($key)) {
            $result[$indexByKey[$key]] = $row
        }
        else {
            $indexByKey[$key] = $result.Count
            $result.Add($row)
        }
    }
    return $result.ToArray()
}

if (-not $BaseTemplateConfigName -and -not $CustomTemplateConfigName) {
    Write-MessageError "BaseTemplateConfigName または CustomTemplateConfigName を指定してください"
    exit 1
}
if (-not $DownloadConfigName) {
    Write-MessageError "DownloadConfigName を指定してください"
    exit 1
}

$baseTemplatePath = $null
$customTemplatePath = $null

if ($BaseTemplateConfigName) {
    $baseTemplatePath = Join-Path $BaseTemplateRoot "$BaseTemplateConfigName.xlsx"
}
if ($CustomTemplateConfigName) {
    $customTemplatePath = Join-Path $CustomTemplateRoot "$CustomTemplateConfigName.xlsx"
}

$downloadPath = Join-Path $DownloadRoot "${DownloadConfigName}_download.xlsx"
$outputPath = Join-Path $ConfigRoot "${DownloadConfigName}_config.xlsx"
$logFilePath = New-WorkerLogPath -LogRoot $LogRoot -Prefix "${LogNamePrefix}-$TargetGroupName-$DownloadConfigName"

$script:exitCode = 0
$psParams = $PSBoundParameters
try {
    & {
        try {
            $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

            if ($baseTemplatePath) {
                $excel = New-Object -ComObject Excel.Application
                $excel.Visible = $false
                $excel.DisplayAlerts = $false
                $excel.ScreenUpdating = $false
                $excel.EnableEvents = $false
                try {
                    $workbook = $excel.Workbooks.Open($baseTemplatePath)
                    $baseSpaceRow = Get-RowObjects -Sheet $workbook.Sheets.Item("space-settings") | Select-Object -First 1
                    $baseMemberRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-member-list"))
                    $baseAppRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-list") | Where-Object { $_.'アプリ名' })
                    $baseAclRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-acl"))
                    $baseRecordAclRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-record-acl"))
                }
                finally {
                    if ($workbook) {
                        try { $workbook.Close($false) } catch {}
                        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook)
                        $workbook = $null
                    }
                    if ($excel) {
                        try { $excel.Quit() } catch {}
                        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
                        $excel = $null
                    }
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                    [System.GC]::Collect()
                }

                Start-Sleep -Milliseconds 100
            }
            else {
                $baseSpaceRow = $null
                $baseMemberRows = @()
                $baseAppRows = @()
                $baseAclRows = @()
                $baseRecordAclRows = @()
            }

            if ($customTemplatePath) {
                $excel = New-Object -ComObject Excel.Application
                $excel.Visible = $false
                $excel.DisplayAlerts = $false
                $excel.ScreenUpdating = $false
                $excel.EnableEvents = $false
                try {
                    $workbook = $excel.Workbooks.Open($customTemplatePath)
                    $customSpaceRow = Get-RowObjects -Sheet $workbook.Sheets.Item("space-settings") | Select-Object -First 1
                    $customMemberRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-member-list"))
                    $customAppRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-list") | Where-Object { $_.'アプリ名' })
                    $customAclRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-acl"))
                    $customRecordAclRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-record-acl"))
                }
                finally {
                    if ($workbook) {
                        try { $workbook.Close($false) } catch {}
                        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook)
                        $workbook = $null
                    }
                    if ($excel) {
                        try { $excel.Quit() } catch {}
                        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
                        $excel = $null
                    }
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                    [System.GC]::Collect()
                }
            }
            else {
                $customSpaceRow = $null
                $customMemberRows = @()
                $customAppRows = @()
                $customAclRows = @()
                $customRecordAclRows = @()
            }

            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $excel.ScreenUpdating = $false
            $excel.EnableEvents = $false
            try {
                $workbook = $excel.Workbooks.Open($downloadPath)
                $downloadSpaceRow = Get-RowObjects -Sheet $workbook.Sheets.Item("space-settings") | Select-Object -First 1
                $downloadMemberRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-member-list"))
                $downloadAppRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-list") | Where-Object { $_.'アプリID' })
                $downloadAclRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-acl"))
                $downloadRecordAclRows = @(Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-record-acl"))

                $downloadHeaders = @{
                    "space-settings"       = @(Get-HeaderRow -Sheet $workbook.Sheets.Item("space-settings"))
                    "space-member-list"    = @(Get-HeaderRow -Sheet $workbook.Sheets.Item("space-member-list"))
                    "space-app-list"       = @(Get-HeaderRow -Sheet $workbook.Sheets.Item("space-app-list"))
                    "space-app-acl"        = @(Get-HeaderRow -Sheet $workbook.Sheets.Item("space-app-acl"))
                    "space-app-record-acl" = @(Get-HeaderRow -Sheet $workbook.Sheets.Item("space-app-record-acl"))
                }
                Write-Message "ダウンロードファイルのヘッダ:" -Type "Info"
                $downloadHeaders.GetEnumerator() | ForEach-Object { Write-Message "  $($_.Key): $($_.Value -join ', ')" -Type "Info" }
            }
            finally {
                if ($workbook) {
                    try { $workbook.Close($false) } catch {}
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook)
                    $workbook = $null
                }
                if ($excel) {
                    try { $excel.Quit() } catch {}
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
                    $excel = $null
                }
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
            }

            Start-Sleep -Milliseconds 100

            if (-not $downloadSpaceRow) {
                throw "ダウンロード結果のspace-settingsが空です"
            }
            $newSpaceId = $downloadSpaceRow.'スペースID'

            $primarySpaceRow = if ($baseSpaceRow) { $baseSpaceRow } else { $customSpaceRow }
            if (-not $primarySpaceRow) {
                throw "テンプレートのspace-settingsが空です"
            }

            $templateSpaceRow = [PSCustomObject]@{
                'スペース名'                            = Get-PreferredValue $customSpaceRow.'スペース名' $primarySpaceRow.'スペース名'
                '参加メンバーだけにこのスペースを公開する'             = Get-PreferredValue $customSpaceRow.'参加メンバーだけにこのスペースを公開する' $primarySpaceRow.'参加メンバーだけにこのスペースを公開する'
                'スペースのポータルと複数のスレッドを使用する'           = Get-PreferredValue $customSpaceRow.'スペースのポータルと複数のスレッドを使用する' $primarySpaceRow.'スペースのポータルと複数のスレッドを使用する'
                'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する' = Get-PreferredValue $customSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する' $primarySpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する'
                'アプリ作成できるユーザーをスペースの管理者に限定する'       = Get-PreferredValue $customSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する' $primarySpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する'
            }
            $spaceNameSource = if ($PreferredDataSource -eq "Download") { $downloadSpaceRow.'スペース名' } else { $templateSpaceRow.'スペース名' }
            $finalSpaceName = Expand-KintonePlaceholder -Value $spaceNameSource -ConfigName $DownloadConfigName

            $templateMemberRows = @(Merge-KintoneRowsByKey -BaseRows $baseMemberRows -CustomRows $customMemberRows -KeyProperties @("種別", "ユーザー/組織/グループ"))

            $baseAppMapping = if ($baseAppRows.Count -gt 0) { Get-AppNameMapping -TemplateApps $baseAppRows -DownloadApps $downloadAppRows } else { @() }
            $customAppMapping = if ($customAppRows.Count -gt 0) { Get-AppNameMapping -TemplateApps $customAppRows -DownloadApps $downloadAppRows } else { @() }

            $baseAppMappingByDownloadId = @{}
            foreach ($m in $baseAppMapping) {
                if ($m.DownloadAppId) { $baseAppMappingByDownloadId[$m.DownloadAppId] = $m }
            }
            $customAppMappingByDownloadId = @{}
            foreach ($m in $customAppMapping) {
                if ($m.DownloadAppId) { $customAppMappingByDownloadId[$m.DownloadAppId] = $m }
            }

            $matchedApps = @($downloadAppRows | ForEach-Object {
                    $dlApp = $_
                    $baseMatch = $baseAppMappingByDownloadId[$dlApp.'アプリID']
                    $customMatch = $customAppMappingByDownloadId[$dlApp.'アプリID']
                    $baseTemplateAppName = if ($baseMatch -and $baseMatch.Status -eq "対応") { $baseMatch.TemplateAppName } else { $null }
                    $customTemplateAppName = if ($customMatch -and $customMatch.Status -eq "対応") { $customMatch.TemplateAppName } else { $null }
                    $finalTemplateAppName = if ($customTemplateAppName) { $customTemplateAppName } else { $baseTemplateAppName }
                    $finalAppName = if ($finalTemplateAppName) { Expand-KintonePlaceholder -Value $finalTemplateAppName -ConfigName $DownloadConfigName } else { $dlApp.'アプリ名' }
                    [PSCustomObject]@{
                        DownloadAppId         = $dlApp.'アプリID'
                        DownloadAppName       = $dlApp.'アプリ名'
                        BaseTemplateAppName   = $baseTemplateAppName
                        CustomTemplateAppName = $customTemplateAppName
                        TemplateAppName       = $finalTemplateAppName
                        FinalAppName          = $finalAppName
                    }
                })

            $unmatchedBaseTemplateApps = @($baseAppMapping | Where-Object { $_.Status -ne "対応" -and $_.TemplateAppName })
            $unmatchedCustomTemplateApps = @($customAppMapping | Where-Object { $_.Status -ne "対応" -and $_.TemplateAppName })
            $unmatchedDownloadApps = @($matchedApps | Where-Object { -not $_.BaseTemplateAppName -and -not $_.CustomTemplateAppName })
            $hasUnmatched = ($unmatchedBaseTemplateApps.Count -gt 0) -or ($unmatchedCustomTemplateApps.Count -gt 0) -or ($unmatchedDownloadApps.Count -gt 0)

            if ($hasUnmatched) {
                Write-Message "" -Type "Info" -NoHeader
                Write-Message "## アプリの対応付けで確認が必要な項目" -Type "Info" -NoHeader
                if ($BaseTemplateConfigName) {
                    foreach ($m in $unmatchedBaseTemplateApps) {
                        Write-Message "  設定テンプレート（基本）のアプリ[$($m.TemplateAppName)]に対応する新スペースのアプリが見つかりません" -ForegroundColor Yellow -Type "Info" -NoHeader
                    }
                }
                if ($CustomTemplateConfigName) {
                    foreach ($m in $unmatchedCustomTemplateApps) {
                        Write-Message "  設定テンプレート（カスタム）のアプリ[$($m.TemplateAppName)]に対応する新スペースのアプリが見つかりません" -ForegroundColor Yellow -Type "Info" -NoHeader
                    }
                }
                foreach ($m in $unmatchedDownloadApps) {
                    Write-Message "  新スペースのアプリ[$($m.DownloadAppName)](appId=$($m.DownloadAppId))に対応するテンプレートのアプリが見つかりません" -ForegroundColor Yellow -Type "Info" -NoHeader
                }
            }

            $spaceRowSource = if ($PreferredDataSource -eq "Download") { $downloadSpaceRow } else { $templateSpaceRow }

            $outSpaceRow = [PSCustomObject]@{
                "スペースID"                           = $newSpaceId
                "スペース名"                            = $finalSpaceName
                "参加メンバーだけにこのスペースを公開する"             = $spaceRowSource.'参加メンバーだけにこのスペースを公開する'
                "スペースのポータルと複数のスレッドを使用する"           = $spaceRowSource.'スペースのポータルと複数のスレッドを使用する'
                "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する" = $spaceRowSource.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する'
                "アプリ作成できるユーザーをスペースの管理者に限定する"       = $spaceRowSource.'アプリ作成できるユーザーをスペースの管理者に限定する'
            }
            New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $excel.ScreenUpdating = $false
            $excel.EnableEvents = $false
            $workbook = $excel.Workbooks.Add()
            while ($workbook.Sheets.Count -gt 1) {
                $workbook.Sheets.Item($workbook.Sheets.Count).Delete()
            }
            $script:outputUsedDefaultSheet = $false
            function New-OutputSheet {
                param([string]$Name)
                if (-not $script:outputUsedDefaultSheet) {
                    $ws = $workbook.Sheets.Item(1)
                    $script:outputUsedDefaultSheet = $true
                }
                else {
                    $ws = $workbook.Sheets.Add([Type]::Missing, $workbook.Sheets.Item($workbook.Sheets.Count))
                }
                $ws.Name = $Name
                return $ws
            }

            $headers = $downloadHeaders["space-settings"]
            $ws = New-OutputSheet "space-settings"
            $rows = @($outSpaceRow)
            $excelDatas = @()
            $excelDatas += , @($headers)
            foreach ($row in $rows) {
                $rowData = @($headers | ForEach-Object { "$($row.$_)" })
                $excelDatas += , $rowData
            }
            Write-BodyDatas -StartCell $ws.Range("A1") -Datas $excelDatas
            Write-Message "" -Type "Info" -NoHeader
            Write-Message "# スペースID: $newSpaceId ($finalSpaceName)" -Type "Info" -NoHeader
            Write-ApplyStepResult -ActionLabel "スペース名を設定しました" -DetailLines @("　$finalSpaceName")
            $spaceRightLines = @('参加メンバーだけにこのスペースを公開する', 'スペースのポータルと複数のスレッドを使用する', 'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する', 'アプリ作成できるユーザーをスペースの管理者に限定する') | ForEach-Object {
                "　${_}: $($outSpaceRow.$_)"
            }
            Write-ApplyStepResult -ActionLabel "スペース権限を設定しました" -DetailLines $spaceRightLines

            if ($PreferredDataSource -eq "Template") {
                $templateMemberCodes = @($templateMemberRows | ForEach-Object { $_.'ユーザー/組織/グループ' })
                $keptMemberRows = @($downloadMemberRows | Where-Object { $templateMemberCodes -notcontains $_.'ユーザー/組織/グループ' })
                $outMemberRows = @($templateMemberRows | ForEach-Object {
                        [PSCustomObject]@{
                            "スペースID"       = $newSpaceId
                            "種別"           = $_.'種別'
                            "ユーザー/組織/グループ" = $_.'ユーザー/組織/グループ'
                            "管理者"          = $_.'管理者'
                            "下位組織も含める"     = $_.'下位組織も含める'
                        }
                    }) + @($keptMemberRows | ForEach-Object {
                        [PSCustomObject]@{
                            "スペースID"       = $newSpaceId
                            "種別"           = $_.'種別'
                            "ユーザー/組織/グループ" = $_.'ユーザー/組織/グループ'
                            "管理者"          = $_.'管理者'
                            "下位組織も含める"     = $_.'下位組織も含める'
                        }
                    })
            }
            else {
                $outMemberRows = @($downloadMemberRows | ForEach-Object {
                        $dlMember = $_
                        $tmplMember = $templateMemberRows | Where-Object { $_.'種別' -eq $dlMember.'種別' -and $_.'ユーザー/組織/グループ' -eq $dlMember.'ユーザー/組織/グループ' } | Select-Object -First 1
                        [PSCustomObject]@{
                            "スペースID"       = $newSpaceId
                            "種別"           = $dlMember.'種別'
                            "ユーザー/組織/グループ" = $dlMember.'ユーザー/組織/グループ'
                            "管理者"          = if ($tmplMember) { $tmplMember.'管理者' } else { $dlMember.'管理者' }
                            "下位組織も含める"     = if ($tmplMember) { $tmplMember.'下位組織も含める' } else { $dlMember.'下位組織も含める' }
                        }
                    })
                $keptMemberRows = $outMemberRows
            }
            $headers = $downloadHeaders["space-member-list"]
            $ws = New-OutputSheet "space-member-list"
            $rows = $outMemberRows
            $excelDatas = @()
            $excelDatas += , @($headers)
            foreach ($row in $rows) {
                $rowData = @($headers | ForEach-Object { "$($row.$_)" })
                $excelDatas += , $rowData
            }
            Write-BodyDatas -StartCell $ws.Range("A1") -Datas $excelDatas
            Write-Message "" -Type "Info" -NoHeader
            $memberDetailLines = @()
            if ($templateMemberRows.Count -gt 0) {
                $memberDetailLines += "　テンプレート内のメンバー ($($templateMemberRows.Count)件)"
                $memberDetailLines += @($templateMemberRows | ForEach-Object {
                        $row = $_
                        $flags = @('管理者', '下位組織も含める') | Where-Object { ToBool $row.$_ }
                        "　　$($row.'種別'):$($row.'ユーザー/組織/グループ') - $($flags -join ',')"
                    })
            }
            if ($keptMemberRows.Count -gt 0) {
                $labelPhrase = if ($PreferredDataSource -eq "Template") { "テンプレート外のメンバー" } else { "ダウンロード側のメンバー（テンプレート上書き済み）" }
                $memberDetailLines += "  $labelPhrase ($($keptMemberRows.Count)件)"
                $memberDetailLines += @($keptMemberRows | ForEach-Object {
                        $row = $_
                        $flags = @('管理者', '下位組織も含める') | Where-Object { ToBool $row.$_ }
                        "　　$($row.'種別'):$($row.'ユーザー/組織/グループ') - $($flags -join ',')"
                    })
            }
            Write-ApplyStepResult -ActionLabel "スペースメンバーを設定しました" -CountPhrase "$($outMemberRows.Count)件" -DetailLines $memberDetailLines

            if ($PreferredDataSource -eq "Template") {
                $outAppRows = @($matchedApps | Where-Object { $_.BaseTemplateAppName -or $_.CustomTemplateAppName } | ForEach-Object {
                        [PSCustomObject]@{ "アプリID" = $_.DownloadAppId; "アプリ名" = $_.FinalAppName }
                    })
            }
            else {
                $outAppRows = @($matchedApps | ForEach-Object {
                        [PSCustomObject]@{ "アプリID" = $_.DownloadAppId; "アプリ名" = $_.FinalAppName }
                    })
            }
            $headers = $downloadHeaders["space-app-list"]
            $ws = New-OutputSheet "space-app-list"
            $rows = $outAppRows
            $excelDatas = @()
            $excelDatas += , @($headers)
            foreach ($row in $rows) {
                $rowData = @($headers | ForEach-Object { "$($row.$_)" })
                $excelDatas += , $rowData
            }
            Write-BodyDatas -StartCell $ws.Range("A1") -Datas $excelDatas

            $outAclRows = New-Object System.Collections.Generic.List[psobject]
            $aclRowSources = New-Object System.Collections.Generic.List[psobject]
            $outRecordAclRows = New-Object System.Collections.Generic.List[psobject]
            $recordAclRowSources = New-Object System.Collections.Generic.List[psobject]

            $appsToProcess = if ($PreferredDataSource -eq "Template") {
                @($matchedApps | Where-Object { $_.BaseTemplateAppName -or $_.CustomTemplateAppName })
            } else {
                $matchedApps
            }

            foreach ($m in $appsToProcess) {
                Write-Message "" -Type "Info" -NoHeader
                Write-Message "## アプリID: $($m.DownloadAppId) ($($m.FinalAppName)) ===" -Type "Info" -NoHeader

                Write-ApplyStepResult -ActionLabel "アプリ名を設定しました" -DetailLines @("　$($m.FinalAppName)")

                $baseAclRowsForApp = if ($m.BaseTemplateAppName) { @($baseAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.BaseTemplateAppName)" }) } else { @() }
                $customAclRowsForApp = if ($m.CustomTemplateAppName) { @($customAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.CustomTemplateAppName)" }) } else { @() }
                $templateAclRows = @(Merge-KintoneRowsByKey -BaseRows $baseAclRowsForApp -CustomRows $customAclRowsForApp -KeyProperties @("種別", "ユーザー／組織／グループ"))

                if ($PreferredDataSource -eq "Template") {
                    $aclRows = $templateAclRows
                }
                else {
                    $downloadAclRowsForApp = @($downloadAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.DownloadAppName)" })
                    $aclRows = @(Merge-KintoneRowsByKey -BaseRows $downloadAclRowsForApp -CustomRows $templateAclRows -KeyProperties @("種別", "ユーザー／組織／グループ"))
                }
                $aclTargetLines = @($aclRows | ForEach-Object {
                        $row = $_
                        $grantedRights = @('レコード閲覧', 'レコード追加', 'レコード編集', 'レコード削除', 'アプリ管理', 'ファイル読み込み', 'ファイル書き出し') | Where-Object { ToBool $row.$_ }
                        "　$($row.'種別'):$($row.'ユーザー／組織／グループ') - $($grantedRights -join ',')"
                    })
                foreach ($r in $aclRows) {
                    $outAclRows.Add([PSCustomObject]@{
                            "アプリID"        = $m.DownloadAppId
                            "アプリ名"         = $m.FinalAppName
                            "種別"           = $r.'種別'
                            "ユーザー／組織／グループ" = $r.'ユーザー／組織／グループ'
                            "レコード閲覧"       = $r.'レコード閲覧'
                            "レコード追加"       = $r.'レコード追加'
                            "レコード編集"       = $r.'レコード編集'
                            "レコード削除"       = $r.'レコード削除'
                            "アプリ管理"        = $r.'アプリ管理'
                            "ファイル読み込み"     = $r.'ファイル読み込み'
                            "ファイル書き出し"     = $r.'ファイル書き出し'
                        })
                    $aclRowSources.Add([PSCustomObject]@{ DownloadAppName = $m.DownloadAppName; TemplateRow = $r })
                }
                Write-ApplyStepResult -ActionLabel "アプリの権限を設定しました" -CountPhrase "$($aclRows.Count)件" -DetailLines $aclTargetLines

                $baseRecordAclRowsForApp = if ($m.BaseTemplateAppName) { @($baseRecordAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.BaseTemplateAppName)" }) } else { @() }
                $customRecordAclRowsForApp = if ($m.CustomTemplateAppName) { @($customRecordAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.CustomTemplateAppName)" }) } else { @() }
                $templateRecordAclRows = @(Merge-KintoneRowsByKey -BaseRows $baseRecordAclRowsForApp -CustomRows $customRecordAclRowsForApp -KeyProperties @("レコードの条件", "種別", "ユーザー／組織／グループ"))

                if ($PreferredDataSource -eq "Template") {
                    $recordAclRows = $templateRecordAclRows
                }
                else {
                    $downloadRecordAclRowsForApp = @($downloadRecordAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.DownloadAppName)" })
                    $recordAclRows = @(Merge-KintoneRowsByKey -BaseRows $downloadRecordAclRowsForApp -CustomRows $templateRecordAclRows -KeyProperties @("レコードの条件", "種別", "ユーザー／組織／グループ"))
                }
                $recordAclCondGroups = @($recordAclRows | Group-Object -Property 'レコードの条件')
                $recordAclTargetLines = @($recordAclCondGroups | ForEach-Object {
                        $condGroup = $_
                        $condLabel = if ($condGroup.Name) { $condGroup.Name } else { "すべてのレコード" }
                        "　条件: $condLabel"
                        "　　対象"
                        foreach ($row in $condGroup.Group) {
                            $grantedRights = @('閲覧', '編集', '削除') | Where-Object { ToBool $row.$_ }
                            $rightsLabel = if ($grantedRights.Count -gt 0) { $grantedRights -join ',' } else { "権限なし" }
                            "　　　- $($row.'種別'):$($row.'ユーザー／組織／グループ') ($rightsLabel)"
                        }
                    })
                foreach ($r in $recordAclRows) {
                    $outRecordAclRows.Add([PSCustomObject]@{
                            "アプリID"        = $m.DownloadAppId
                            "アプリ名"         = $m.FinalAppName
                            "レコードの条件"      = $r.'レコードの条件'
                            "種別"           = $r.'種別'
                            "ユーザー／組織／グループ" = $r.'ユーザー／組織／グループ'
                            "閲覧"           = $r.'閲覧'
                            "編集"           = $r.'編集'
                            "削除"           = $r.'削除'
                        })
                    $recordAclRowSources.Add([PSCustomObject]@{ DownloadAppName = $m.DownloadAppName; TemplateRow = $r })
                }
                Write-ApplyStepResult -ActionLabel "アプリのレコード権限を設定しました" -CountPhrase "条件$($recordAclCondGroups.Count)件、対象$($recordAclRows.Count)件" -DetailLines $recordAclTargetLines
            }

            $headers = $downloadHeaders["space-app-acl"]
            $ws = New-OutputSheet "space-app-acl"
            $rows = $outAclRows.ToArray()
            $excelDatas = @()
            $excelDatas += , @($headers)
            foreach ($row in $rows) {
                $rowData = @($headers | ForEach-Object { "$($row.$_)" })
                $excelDatas += , $rowData
            }
            Write-BodyDatas -StartCell $ws.Range("A1") -Datas $excelDatas
            $headers = $downloadHeaders["space-app-record-acl"]
            $ws = New-OutputSheet "space-app-record-acl"
            $rows = $outRecordAclRows.ToArray()
            $excelDatas = @()
            $excelDatas += , @($headers)
            foreach ($row in $rows) {
                $rowData = @($headers | ForEach-Object { "$($row.$_)" })
                $excelDatas += , $rowData
            }
            Write-BodyDatas -StartCell $ws.Range("A1") -Datas $excelDatas

            foreach ($sheetName in @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl")) {
                Set-HeaderRowColor -Sheet $workbook.Sheets.Item($sheetName) -Color ([System.Drawing.Color]::FromArgb(217, 217, 217))
            }
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()

            $applyDiffColoring = $true

            $diffColor = [System.Drawing.Color]::FromArgb(255, 0, 0)
            $diffColorOle = ConvertTo-OleColor $diffColor

            try {
                function Set-KintoneCellDiffColor {
                    param($Cell, [string]$DownloadValue, [string]$FinalValue)
                    if ($DownloadValue -eq $FinalValue) { return }
                    $Cell.Font.Color = $diffColorOle
                    $Cell.Font.Bold = $true
                }

                if ($applyDiffColoring) {
                    $wsSettings = $workbook.Sheets.Item("space-settings")
                    Set-PlaceholderRichText -Cell $wsSettings.Cells.Item(2, 2) -OriginalValue $spaceNameSource -Replacement $DownloadConfigName -Color $diffColor
                    Set-KintoneCellDiffColor -Cell $wsSettings.Cells.Item(2, 3) -DownloadValue "$($downloadSpaceRow.'参加メンバーだけにこのスペースを公開する')" -FinalValue "$($outSpaceRow.'参加メンバーだけにこのスペースを公開する')"
                    Set-KintoneCellDiffColor -Cell $wsSettings.Cells.Item(2, 4) -DownloadValue "$($downloadSpaceRow.'スペースのポータルと複数のスレッドを使用する')" -FinalValue "$($outSpaceRow.'スペースのポータルと複数のスレッドを使用する')"
                    Set-KintoneCellDiffColor -Cell $wsSettings.Cells.Item(2, 5) -DownloadValue "$($downloadSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する')" -FinalValue "$($outSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する')"
                    Set-KintoneCellDiffColor -Cell $wsSettings.Cells.Item(2, 6) -DownloadValue "$($downloadSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')" -FinalValue "$($outSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')"

                    $wsAppList = $workbook.Sheets.Item("space-app-list")
                    $appsForDiffColor = if ($PreferredDataSource -eq "Template") {
                        @($matchedApps | Where-Object { $_.BaseTemplateAppName -or $_.CustomTemplateAppName })
                    } else {
                        $matchedApps
                    }
                    for ($i = 0; $i -lt $appsForDiffColor.Count; $i++) {
                        Set-PlaceholderRichText -Cell $wsAppList.Cells.Item(($i + 2), 2) -OriginalValue $appsForDiffColor[$i].TemplateAppName -Replacement $DownloadConfigName -Color $diffColor
                    }

                    $wsMember = $null
                    try { $wsMember = $workbook.Sheets.Item("space-member-list") } catch { $wsMember = $null }
                    if ($wsMember) {
                        $memberUsed = $wsMember.UsedRange
                        $memberLastRow = $memberUsed.Row + $memberUsed.Rows.Count - 1
                        $memberLastCol = $memberUsed.Column + $memberUsed.Columns.Count - 1
                        $memberRowsForDiffColor = if ($PreferredDataSource -eq "Template") { $templateMemberRows } else { $downloadMemberRows }
                        $templateRowEnd = [Math]::Min(1 + $memberRowsForDiffColor.Count, $memberLastRow)
                        for ($row = 2; $row -le $templateRowEnd; $row++) {
                            $tmplRow = $memberRowsForDiffColor[$row - 2]
                            $dlRow = $downloadMemberRows | Where-Object {
                                "$($_.'種別')" -eq "$($tmplRow.'種別')" -and
                                "$($_.'ユーザー/組織/グループ')" -eq "$($tmplRow.'ユーザー/組織/グループ')"
                            } | Select-Object -First 1
                            if (-not $dlRow) {
                                for ($col = 1; $col -le $memberLastCol; $col++) {
                                    $wsMember.Cells.Item($row, $col).Font.Color = $diffColorOle
                                    $wsMember.Cells.Item($row, $col).Font.Bold = $true
                                }
                                continue
                            }
                            $outMemberRow = $outMemberRows[$row - 2]
                            Set-KintoneCellDiffColor -Cell $wsMember.Cells.Item($row, 4) -DownloadValue "$($dlRow.'管理者')" -FinalValue "$($outMemberRow.'管理者')"
                            Set-KintoneCellDiffColor -Cell $wsMember.Cells.Item($row, 5) -DownloadValue "$($dlRow.'下位組織も含める')" -FinalValue "$($outMemberRow.'下位組織も含める')"
                        }
                    }

                    $wsAcl = $null
                    try { $wsAcl = $workbook.Sheets.Item("space-app-acl") } catch { $wsAcl = $null }
                    if ($wsAcl) {
                        $aclUsed = $wsAcl.UsedRange
                        $aclLastRow = $aclUsed.Row + $aclUsed.Rows.Count - 1
                        $aclLastCol = $aclUsed.Column + $aclUsed.Columns.Count - 1
                        for ($i = 0; $i -lt $aclRowSources.Count; $i++) {
                            $row = $i + 2
                            if ($row -gt $aclLastRow) { break }
                            $src = $aclRowSources[$i]
                            $tmplRow = $src.TemplateRow
                            $dlRow = $downloadAclRows | Where-Object {
                                "$($_.'アプリ名')" -eq "$($src.DownloadAppName)" -and
                                "$($_.'種別')" -eq "$($tmplRow.'種別')" -and
                                "$($_.'ユーザー／組織／グループ')" -eq "$($tmplRow.'ユーザー／組織／グループ')"
                            } | Select-Object -First 1
                            if (-not $dlRow) {
                                for ($col = 1; $col -le $aclLastCol; $col++) {
                                    $wsAcl.Cells.Item($row, $col).Font.Color = $diffColorOle
                                    $wsAcl.Cells.Item($row, $col).Font.Bold = $true
                                }
                                continue
                            }
                            $outAclRow = $outAclRows.ToArray()[$row - 2]
                            Set-KintoneCellDiffColor -Cell $wsAcl.Cells.Item($row, 5) -DownloadValue "$($dlRow.'レコード閲覧')" -FinalValue "$($outAclRow.'レコード閲覧')"
                            Set-KintoneCellDiffColor -Cell $wsAcl.Cells.Item($row, 6) -DownloadValue "$($dlRow.'レコード追加')" -FinalValue "$($outAclRow.'レコード追加')"
                            Set-KintoneCellDiffColor -Cell $wsAcl.Cells.Item($row, 7) -DownloadValue "$($dlRow.'レコード編集')" -FinalValue "$($outAclRow.'レコード編集')"
                            Set-KintoneCellDiffColor -Cell $wsAcl.Cells.Item($row, 8) -DownloadValue "$($dlRow.'レコード削除')" -FinalValue "$($outAclRow.'レコード削除')"
                            Set-KintoneCellDiffColor -Cell $wsAcl.Cells.Item($row, 9) -DownloadValue "$($dlRow.'アプリ管理')" -FinalValue "$($outAclRow.'アプリ管理')"
                            Set-KintoneCellDiffColor -Cell $wsAcl.Cells.Item($row, 10) -DownloadValue "$($dlRow.'ファイル読み込み')" -FinalValue "$($outAclRow.'ファイル読み込み')"
                            Set-KintoneCellDiffColor -Cell $wsAcl.Cells.Item($row, 11) -DownloadValue "$($dlRow.'ファイル書き出し')" -FinalValue "$($outAclRow.'ファイル書き出し')"
                        }
                    }

                    $wsRecordAcl = $null
                    try { $wsRecordAcl = $workbook.Sheets.Item("space-app-record-acl") } catch { $wsRecordAcl = $null }
                    if ($wsRecordAcl) {
                        $recordAclUsed = $wsRecordAcl.UsedRange
                        $recordAclLastRow = $recordAclUsed.Row + $recordAclUsed.Rows.Count - 1
                        for ($i = 0; $i -lt $recordAclRowSources.Count; $i++) {
                            $row = $i + 2
                            if ($row -gt $recordAclLastRow) { break }
                            $src = $recordAclRowSources[$i]
                            $tmplRow = $src.TemplateRow
                            $dlRow = $downloadRecordAclRows | Where-Object {
                                "$($_.'アプリ名')" -eq "$($src.DownloadAppName)" -and
                                "$($_.'レコードの条件')" -eq "$($tmplRow.'レコードの条件')" -and
                                "$($_.'種別')" -eq "$($tmplRow.'種別')" -and
                                "$($_.'ユーザー／組織／グループ')" -eq "$($tmplRow.'ユーザー／組織／グループ')"
                            } | Select-Object -First 1
                            if (-not $dlRow) {
                                for ($col = 1; $col -le $recordAclUsed.Column + $recordAclUsed.Columns.Count - 1; $col++) {
                                    $wsRecordAcl.Cells.Item($row, $col).Font.Color = $diffColorOle
                                    $wsRecordAcl.Cells.Item($row, $col).Font.Bold = $true
                                }
                                continue
                            }
                            $outRecordAclRow = $outRecordAclRows.ToArray()[$row - 2]
                            Set-KintoneCellDiffColor -Cell $wsRecordAcl.Cells.Item($row, 6) -DownloadValue "$($dlRow.'閲覧')" -FinalValue "$($outRecordAclRow.'閲覧')"
                            Set-KintoneCellDiffColor -Cell $wsRecordAcl.Cells.Item($row, 7) -DownloadValue "$($dlRow.'編集')" -FinalValue "$($outRecordAclRow.'編集')"
                            Set-KintoneCellDiffColor -Cell $wsRecordAcl.Cells.Item($row, 8) -DownloadValue "$($dlRow.'削除')" -FinalValue "$($outRecordAclRow.'削除')"
                        }
                    }
                }

                foreach ($sheetName in @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl")) {
                    $ws = $null
                    try { $ws = $workbook.Sheets.Item($sheetName) } catch { $ws = $null }
                    if (-not $ws) { continue }
                    Set-ColumnWidth -Worksheet $ws
                }

                Set-FirstVisibleSheet -Workbook $workbook
                $workbook.SaveAs($outputPath, 51)
            }
            finally {
                if ($workbook) {
                    try { $workbook.Close($false) } catch {}
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook)
                    $workbook = $null
                }
                if ($excel) {
                    try { $excel.Quit() } catch {}
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
                    $excel = $null
                }
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
            }

            Write-MessageComplete "設定内容を出力しました: $outputPath"
            if ($hasUnmatched) {
                $script:exitCode = 2
            }
        }
        catch {
            Write-MessageError "実行エラー: $($error[0])"
            $script:exitCode = 1
        }
    } *>&1 | Tee-Object -FilePath $logFilePath
}
finally {
    ConvertTo-Utf8LogFile -Path $logFilePath
    Write-MessageComplete "ログを出力しました: $logFilePath"
}
exit $script:exitCode
