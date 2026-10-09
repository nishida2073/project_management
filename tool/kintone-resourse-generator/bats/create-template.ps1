# =========================================
# 現在のスペース設定をテンプレートとして作成
# =========================================

param(
    [string]$LogNamePrefix,
    [string]$SpaceId,
    [string]$BaseUrl,
    [string]$TemplateRoot,
    [string]$LogRoot,
    [string]$KintoneLogin,
    [string]$KintonePassword,
    [string]$TargetGroupName,
    [string]$TemplateName,
    [string]$OrgFileName
)

$libraryDir = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -LogRoot $LogRoot -Prefix "${LogNamePrefix}-${TargetGroupName}-${TemplateName}"

$script:exitCode = 0
$psParams = $PSBoundParameters
try {
    & {
        try {
            $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

            if (-not $SpaceId) {
                throw "SpaceId を指定してください。"
            }
            $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${KintoneLogin}:${KintonePassword}"))

            $space = $null
            try {
                $space = Get-CurrentSpace -SpaceId $SpaceId -BaseUrl $BaseUrl -Authorization $authorization
            }
            catch {
                throw "スペース取得に失敗しました: $($_.Exception.Message)"
            }

            Write-Message "" -Type "Info" -NoHeader
            Write-Message "# スペースID: $($space.spaceId) ($($space.spaceName))" -Type "Info" -NoHeader

            Write-ApplyStepResult -ActionLabel "スペース名を取得しました" -DetailLines @("　$($space.spaceName)")

            $outputDir = Join-Path $TemplateRoot "custom"
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

            $outputPath = Join-Path $outputDir "${TargetGroupName}_${TemplateName}.xlsx"

            $templateFile = Join-Path $TemplateRoot $OrgFileName
            if (-not (Test-Path $templateFile)) {
                throw "テンプレートファイルが見つかりません: $templateFile"
            }

            Copy-Item -Path $templateFile -Destination $outputPath -Force

            Write-ApplyStepResult -ActionLabel "テンプレートファイルを作成しました" -DetailLines @("　$outputPath")

            $spaceListRows = @([PSCustomObject]@{
                    "スペース名"                            = "{PH}"
                    "参加メンバーだけにこのスペースを公開する"             = $space.isPrivate
                    "スペースのポータルと複数のスレッドを使用する"           = $space.useMultiThread
                    "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する" = $space.fixedMember
                    "アプリ作成できるユーザーをスペースの管理者に限定する"       = ($space.createApp -eq "ADMIN")
                })

            $memberRows = @($space.members | ForEach-Object {
                    [PSCustomObject]@{
                        "種別"           = Get-KintoneMemberTypeLabel $_.entity.type
                        "ユーザー/組織/グループ" = $_.entity.code
                        "管理者"          = $_.isAdmin
                        "下位組織も含める"     = $_.includeSubs
                    }
                })

            $appListRows = @($space.apps | ForEach-Object {
                    [PSCustomObject]@{
                        "アプリID" = $_.appId
                        "アプリ名"  = $_.name
                    }
                })

            $appAclRows = @()
            foreach ($app in $space.apps) {
                foreach ($right in $app.rights) {
                    if ($right.entity.type -eq "CREATOR") { continue }
                    $appAclRows += [PSCustomObject]@{
                        "アプリ名"         = $app.name
                        "種別"           = Get-KintoneMemberTypeLabel $right.entity.type
                        "ユーザー／組織／グループ" = $right.entity.code
                        "レコード閲覧"       = $right.recordViewable
                        "レコード追加"       = $right.recordAddable
                        "レコード編集"       = $right.recordEditable
                        "レコード削除"       = $right.recordDeletable
                        "アプリ管理"        = $right.appEditable
                        "ファイル読み込み"     = $right.recordImportable
                        "ファイル書き出し"     = $right.recordExportable
                    }
                }
            }

            $recordAclRows = @()
            foreach ($app in $space.apps) {
                foreach ($right in $app.recordRights) {
                    foreach ($entity in $right.entities) {
                        $isCreator = $entity.entity.type -eq "CREATOR"
                        $orgName = if ($isCreator) { "作成者" } else { $entity.entity.code }
                        $typeLabel = if ($isCreator) { "作成者" } else { Get-KintoneMemberTypeLabel $entity.entity.type }
                        $recordAclRows += [PSCustomObject]@{
                            "アプリ名"         = $app.name
                            "レコードの条件"      = $right.filterCond
                            "種別"           = $typeLabel
                            "ユーザー／組織／グループ" = $orgName
                            "閲覧"           = $entity.viewable
                            "編集"           = $entity.editable
                            "削除"           = $entity.deletable
                        }
                    }
                }
            }

            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $excel.ScreenUpdating = $false
            $excel.EnableEvents = $false
            try {
                $workbook = $excel.Workbooks.Open($outputPath)
                $downloadSheetData = [ordered]@{
                    "space-settings"       = @{ Rows = $spaceListRows; Headers = @("スペース名", "参加メンバーだけにこのスペースを公開する", "スペースのポータルと複数のスレッドを使用する", "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する", "アプリ作成できるユーザーをスペースの管理者に限定する") }
                    "space-member-list"    = @{ Rows = $memberRows; Headers = @("種別", "ユーザー/組織/グループ", "管理者", "下位組織も含める") }
                    "space-app-list"       = @{ Rows = $appListRows; Headers = @("アプリ名") }
                    "space-app-acl"        = @{ Rows = $appAclRows; Headers = @("アプリ名", "種別", "ユーザー／組織／グループ", "レコード閲覧", "レコード追加", "レコード編集", "レコード削除", "アプリ管理", "ファイル読み込み", "ファイル書き出し") }
                    "space-app-record-acl" = @{ Rows = $recordAclRows; Headers = @("アプリ名", "レコードの条件", "種別", "ユーザー／組織／グループ", "閲覧", "編集", "削除") }
                }
                foreach ($sheetName in $downloadSheetData.Keys) {
                    $ws = $workbook.Sheets.Item($sheetName)
                    $headers = $downloadSheetData[$sheetName].Headers
                    $rows = $downloadSheetData[$sheetName].Rows | Sort-Object -Property $headers[0]
                    if ($headers.Count -eq 0 -and $rows.Count -gt 0) {
                        $headers = @($rows[0].PSObject.Properties.Name)
                    }
                    $excelDatas = @()
                    foreach ($row in $rows) {
                        $rowData = @($headers | ForEach-Object { "$($row.$_)" })
                        $excelDatas += , $rowData
                    }
                    Write-BodyDatas -StartCell $ws.Range("A2") -Datas $excelDatas
                }

                Set-FirstVisibleSheet -Workbook $workbook
                $workbook.Save()

                Write-MessageComplete "テンプレートを作成しました: $outputPath"
            }
            finally {
                if ($workbook) { $workbook.Close($false); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
                if ($excel) { $excel.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
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
