# =========================================
# 現在のスペースの状態をExcelへ書き出す
# =========================================
# 指定したスペースIDの現在の状態を download\<CONFIG_NAME>.xlsx のシート
# （space-settings / space-member-list / space-app-list / space-app-acl / space-app-record-acl）に書き出す。
# 対象の5シートは毎回完全に上書きする。

param(
    [string]$SpaceId,
    [string]$ConfigName
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "library\common.ps1")

$baseUrl = $env:KINTONE_BASE_URL
$downloadRoot = $env:COMMON_DOWNLOAD_PATH
$logRoot = $env:COMMON_LOG_PATH

if (-not $baseUrl -or -not $downloadRoot -or -not $logRoot) {
    Write-Message "KINTONE_BASE_URL / COMMON_DOWNLOAD_PATH / COMMON_LOG_PATH を設定してください（clients\set-kintone.bat・set-env.bat）" -Type "Info" -NoHeader
    exit 1
}
if (-not $SpaceId) {
    $SpaceId = Read-Host "ダウンロード対象のスペースID"
}
# 設定ファイル名（ConfigName）は省略可能。未指定の場合はダウンロード対象スペースの現在の名前から
# 自動で設定するため、ダウンロード先パスの確定はスペース取得後に行う（ログファイル名だけは
# その時点でConfigNameが未確定のため、代わりにスペースIDを使って先に決めておく）。
$logFilePath = New-WorkerLogPath -LogRoot $logRoot -Prefix "download_$(if ($ConfigName) { $ConfigName } else { "space$SpaceId" })"

$script:exitCode = 0

& {
    $authorization = Get-KintoneAuthorizationHeader -BaseUrl $baseUrl

    $space = $null
    try {
        $space = Get-CurrentSpace -SpaceId $SpaceId -BaseUrl $baseUrl -Authorization $authorization
    } catch {
        Write-Message "スペース取得に失敗しました: $($_.Exception.Message)" -ForegroundColor Red -Type "Info" -NoHeader
        $script:exitCode = 1
        return
    }

    if (-not $ConfigName) {
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        $ConfigName = -join ($space.spaceName.ToCharArray() | ForEach-Object { if ($invalidChars -contains $_) { "_" } else { $_ } })
        # GUI（gui.ps1）が自動設定された設定ファイル名を取得するための機械可読な行。人間向けログの文言とは独立させておく。
        Write-Message "　CONFIG_NAME=$ConfigName" -Type "Info" -NoHeader -Hidden
    }
    $downloadPath = Join-Path $downloadRoot "${ConfigName}_download.xlsx"

    Write-Message "" -Type "Info" -NoHeader
    Write-Message "# スペースID: $($space.spaceId) ($($space.spaceName))" -Type "Info" -NoHeader

    Write-ApplyStepResult -ActionLabel "スペース名を取得しました" -DetailLines @("　$($space.spaceName)")

    $spaceListRows = @([PSCustomObject]@{
        "スペースID"                                                     = $space.spaceId
        "スペース名"                                                     = $space.spaceName
        "参加メンバーだけにこのスペースを公開する"                       = $space.isPrivate
        "スペースのポータルと複数のスレッドを使用する"                   = $space.useMultiThread
        "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する" = $space.fixedMember
        "アプリ作成できるユーザーをスペースの管理者に限定する"           = ($space.createApp -eq "ADMIN")
    })
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-settings" -Rows $spaceListRows -Headers @("スペースID", "スペース名", "参加メンバーだけにこのスペースを公開する", "スペースのポータルと複数のスレッドを使用する", "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する", "アプリ作成できるユーザーをスペースの管理者に限定する")

    $spaceRightLines = @('参加メンバーだけにこのスペースを公開する', 'スペースのポータルと複数のスレッドを使用する', 'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する', 'アプリ作成できるユーザーをスペースの管理者に限定する') | ForEach-Object {
        "　${_}: $($spaceListRows[0].$_)"
    }
    Write-ApplyStepResult -ActionLabel "スペース権限を取得しました" -DetailLines $spaceRightLines

    $memberRows = @($space.members | ForEach-Object {
        [PSCustomObject]@{
            "スペースID"             = $space.spaceId
            "種別"                   = Get-KintoneMemberTypeLabel $_.entity.type
            "ユーザー/組織/グループ" = $_.entity.code
            "管理者"                 = $_.isAdmin
            "下位組織も含める"       = $_.includeSubs
        }
    })
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-member-list" -Rows $memberRows -Headers @("スペースID", "種別", "ユーザー/組織/グループ", "管理者", "下位組織も含める")

    $memberLines = @($memberRows | ForEach-Object {
        $row = $_
        $flags = @('管理者', '下位組織も含める') | Where-Object { ToBool $row.$_ }
        "　　$($row.'種別'):$($row.'ユーザー/組織/グループ') - $($flags -join ',')"
    })
    Write-ApplyStepResult -ActionLabel "スペースメンバーを取得しました" -CountPhrase "$($memberRows.Count)件" -DetailLines $memberLines

    $appListRows = @($space.apps | ForEach-Object {
        [PSCustomObject]@{
            "アプリID" = $_.appId
            "アプリ名" = $_.name
        }
    })
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-list" -Rows $appListRows -Headers @("アプリID", "アプリ名")

    $appAclRows = @()
    foreach ($app in $space.apps) {
        foreach ($right in $app.rights) {
            if ($right.entity.type -eq "CREATOR") { continue }
            $appAclRows += [PSCustomObject]@{
                "アプリID"         = $app.appId
                "アプリ名"         = $app.name
                "種別"             = Get-KintoneMemberTypeLabel $right.entity.type
                "ユーザー／組織／グループ" = $right.entity.code
                "レコード閲覧"     = $right.recordViewable
                "レコード追加"     = $right.recordAddable
                "レコード編集"     = $right.recordEditable
                "レコード削除"     = $right.recordDeletable
                "アプリ管理"       = $right.appEditable
                "ファイル読み込み" = $right.recordImportable
                "ファイル書き出し" = $right.recordExportable
            }
        }
    }
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-acl" -Rows $appAclRows -Headers @("アプリID", "アプリ名", "種別", "ユーザー／組織／グループ", "レコード閲覧", "レコード追加", "レコード編集", "レコード削除", "アプリ管理", "ファイル読み込み", "ファイル書き出し")

    $recordAclRows = @()
    foreach ($app in $space.apps) {
        foreach ($right in $app.recordRights) {
            foreach ($entity in $right.entities) {
                $isCreator = $entity.entity.type -eq "CREATOR"
                $orgName = if ($isCreator) { "作成者" } else { $entity.entity.code }
                $typeLabel = if ($isCreator) { "作成者" } else { Get-KintoneMemberTypeLabel $entity.entity.type }
                $recordAclRows += [PSCustomObject]@{
                    "アプリID"               = $app.appId
                    "アプリ名"               = $app.name
                    "レコードの条件"         = $right.filterCond
                    "種別"                   = $typeLabel
                    "ユーザー／組織／グループ" = $orgName
                    "閲覧"                   = $entity.viewable
                    "編集"                   = $entity.editable
                    "削除"                   = $entity.deletable
                }
            }
        }
    }
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-record-acl" -Rows $recordAclRows -Headers @("アプリID", "アプリ名", "レコードの条件", "種別", "ユーザー／組織／グループ", "閲覧", "編集", "削除")

    Set-KintoneHeaderRowColor -Path $downloadPath -WorksheetNames @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl") -Color ([System.Drawing.Color]::FromArgb(217, 217, 217))

    foreach ($app in $space.apps) {
        Write-Message "" -Type "Info" -NoHeader
        Write-Message "## アプリID: $($app.appId) ($($app.name)) ===" -Type "Info" -NoHeader

        Write-ApplyStepResult -ActionLabel "アプリ名を取得しました" -DetailLines @("　$($app.name)")

        $aclRowsForApp = @($appAclRows | Where-Object { "$($_.'アプリID')" -eq "$($app.appId)" })
        $aclTargetLines = @($aclRowsForApp | ForEach-Object {
            $row = $_
            $grantedRights = @('レコード閲覧', 'レコード追加', 'レコード編集', 'レコード削除', 'アプリ管理', 'ファイル読み込み', 'ファイル書き出し') | Where-Object { ToBool $row.$_ }
            "　$($row.'種別'):$($row.'ユーザー／組織／グループ') - $($grantedRights -join ',')"
        })
        Write-ApplyStepResult -ActionLabel "アプリの権限を取得しました" -CountPhrase "$($aclRowsForApp.Count)件" -DetailLines $aclTargetLines

        $recordAclRowsForApp = @($recordAclRows | Where-Object { "$($_.'アプリID')" -eq "$($app.appId)" })
        $recordAclCondGroups = @($recordAclRowsForApp | Group-Object -Property 'レコードの条件')
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
        Write-ApplyStepResult -ActionLabel "アプリのレコード権限を取得しました" -CountPhrase "条件$($recordAclCondGroups.Count)件、対象$($recordAclRowsForApp.Count)件" -DetailLines $recordAclTargetLines
    }

    Write-Message "" -Type "Info" -NoHeader
    Write-Message "現在の状態を出力しました: $downloadPath" -ForegroundColor Green -Type "Info" -NoHeader
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Message "" -Type "Info" -NoHeader
Write-Message "ログを出力しました: $logFilePath" -ForegroundColor Green -Type "Info" -NoHeader
exit $script:exitCode
