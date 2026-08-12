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
. (Join-Path $scriptDir "common.ps1")

$baseUrl = $env:KINTONE_BASE_URL
$downloadRoot = $env:KINTONE_DOWNLOAD_PATH
$logRoot = $env:KINTONE_LOG_PATH

if (-not $baseUrl -or -not $downloadRoot -or -not $logRoot) {
    Write-Host "KINTONE_BASE_URL / KINTONE_DOWNLOAD_PATH / KINTONE_LOG_PATH を set-env.bat で設定してください"
    exit 1
}
if (-not $SpaceId) {
    $SpaceId = Read-Host "ダウンロード対象のスペースID"
}
if (-not $ConfigName) {
    $ConfigName = Read-Host "設定ファイル名（download\<CONFIG_NAME>_download.xlsx の<CONFIG_NAME>）"
}

$downloadPath = Join-Path $downloadRoot "${ConfigName}_download.xlsx"
$logFilePath = New-KintoneLogPath -LogRoot $logRoot -Prefix "download_$ConfigName"

$script:exitCode = 0

& {
    $authorization = Get-KintoneAuthorizationHeader -BaseUrl $baseUrl

    $space = $null
    try {
        $space = Get-CurrentSpace -SpaceId $SpaceId -BaseUrl $baseUrl -Authorization $authorization
    } catch {
        Write-Host "スペース取得に失敗しました: $($_.Exception.Message)" -ForegroundColor Red
        $script:exitCode = 1
        return
    }

    Write-Host "スペース名: $($space.spaceName)　アプリ数: $($space.apps.Count)　メンバー数: $($space.members.Count)"

    $spaceListRows = @([PSCustomObject]@{
        "スペースID"                                                     = $space.spaceId
        "スペース名"                                                     = $space.spaceName
        "参加メンバーだけにこのスペースを公開する"                       = $space.isPrivate
        "スペースのポータルと複数のスレッドを使用する"                   = $space.useMultiThread
        "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する" = $space.fixedMember
        "アプリ作成できるユーザーをスペースの管理者に限定する"           = ($space.createApp -eq "ADMIN")
    })
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-settings" -Rows $spaceListRows -Headers @("スペースID", "スペース名", "参加メンバーだけにこのスペースを公開する", "スペースのポータルと複数のスレッドを使用する", "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する", "アプリ作成できるユーザーをスペースの管理者に限定する")

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

    Write-Host ""
    Write-Host "現在の状態を出力しました: $downloadPath" -ForegroundColor Green
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Host ""
Write-Host "ログを出力しました: $logFilePath" -ForegroundColor Green
exit $script:exitCode
