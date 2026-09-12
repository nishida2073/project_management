# =========================================
# テンプレートと新スペースのダウンロード結果からconfigを自動生成する
# =========================================
# テンプレート（スペースID・アプリIDを持たず、アプリ名だけで紐づく共通ACL・メンバー設定）と
# ダウンロード結果（新スペースの実ID入り）をアプリ名の一致で対応付けてconfigを生成する。
# 対応付けられなかったアプリはコンソールに一覧表示するので、必要なら手動でconfigに追記する。
# スペース名・アプリ名の"{PH}"は、kintone側で最終名が決まる前の仮名という運用を想定し、
# 設定ファイル名に置き換える。kintoneへの書き込みは行わない。
#
# CustomTemplateConfigName（省略可）を指定すると、設定テンプレート（基本）に加えて設定テンプレート（カスタム）の
# 内容を組み合わせてconfigを生成する。組み合わせ方はシートによって異なる:
#   space-settings         : 項目ごとにcustomの値があれば優先し、無ければbaseの値を使う
#   space-member-list      : base・custom両方の行を残す（追加）。種別+ユーザー/組織/グループが
#                             重複する場合はcustomの行で上書きする
#   space-app-list         : base・custom双方をダウンロード結果と個別にマッチングする。同じ
#                             ダウンロード先アプリに両方が対応した場合、ACLはbase・custom両方の
#                             テンプレートから取得し、警告表示等の代表テンプレートアプリ名はcustomを優先する
#   space-app-acl          : マッチしたアプリごとに、base・custom両方のACL行を残す（追加）。
#   space-app-record-acl     種別+ユーザー／組織／グループ（レコードACLはレコードの条件も含む）が
#                             重複する場合はcustomの行で上書きする

param(
    [string]$BaseTemplateConfigName,
    [string]$CustomTemplateConfigName,
    [string]$DownloadConfigName
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "library\common.ps1")

$baseTemplateRoot = $env:COMMON_BASE_TEMPLATE_PATH
$customTemplateRoot = $env:COMMON_CUSTOM_TEMPLATE_PATH
$configRoot = $env:COMMON_CONFIG_PATH
$downloadRoot = $env:COMMON_DOWNLOAD_PATH
$logRoot = $env:COMMON_LOG_PATH

if (-not $baseTemplateRoot -or -not $configRoot -or -not $downloadRoot -or -not $logRoot) {
    Write-Message "COMMON_BASE_TEMPLATE_PATH / COMMON_CONFIG_PATH / COMMON_DOWNLOAD_PATH / COMMON_LOG_PATH を set-env.bat で設定してください" -Type "Info" -NoHeader
    exit 1
}
if (-not $BaseTemplateConfigName) {
    $BaseTemplateConfigName = Read-Host "設定テンプレート（基本）名"
}
if (-not $DownloadConfigName) {
    $DownloadConfigName = Read-Host "設定ファイル名"
}
if ($CustomTemplateConfigName -and -not $customTemplateRoot) {
    Write-Message "COMMON_CUSTOM_TEMPLATE_PATH を set-env.bat で設定してください" -Type "Info" -NoHeader
    exit 1
}

$baseTemplatePath = Join-Path $baseTemplateRoot "$BaseTemplateConfigName.xlsx"
$customTemplatePath = if ($CustomTemplateConfigName) { Join-Path $customTemplateRoot "$CustomTemplateConfigName.xlsx" } else { $null }
$downloadPath = Join-Path $downloadRoot "${DownloadConfigName}_download.xlsx"
$outputPath = Join-Path $configRoot "${DownloadConfigName}_config.xlsx"
$logFilePath = New-WorkerLogPath -LogRoot $logRoot -Prefix "generate_$DownloadConfigName"

$script:exitCode = 0

# customの値が空でなければcustomを、空ならbaseを返す（space-settingsのフィールド単位のマージに使う）
function Get-PreferredValue {
    param($CustomValue, $BaseValue)
    if ("$CustomValue" -ne "") { return $CustomValue }
    return $BaseValue
}

# 複数行シート（メンバー・ACL・レコードACL）のbaseTemplateとcustomTemplateの結合に使う。
# [KeyProperties]が一致する行はcustomTemplate側で上書きし、一致しない行は両方とも残す（追加）
function Merge-KintoneRowsByKey {
    param(
        [array]$BaseRows,
        [array]$CustomRows,
        [string[]]$KeyProperties
    )
    $result = New-Object System.Collections.Generic.List[psobject]
    $indexByKey = @{}
    # BaseRows/CustomRowsが0件のとき、呼び出し元の「if式の結果を代入」という書き方によって
    # $null（空配列ではなく）になることがあり、@($null)は要素数1の配列（中身はnull）になってしまうため、
    # ここでnull行を明示的に除外する
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
        } else {
            $indexByKey[$key] = $result.Count
            $result.Add($row)
        }
    }
    return $result.ToArray()
}

& {
    $baseSpaceRow = Read-KintoneExcelRows -Path $baseTemplatePath -WorksheetName "space-settings" | Select-Object -First 1
    $baseMemberRows = @(Read-KintoneExcelRows -Path $baseTemplatePath -WorksheetName "space-member-list")
    $baseAppRows = @(Read-KintoneExcelRows -Path $baseTemplatePath -WorksheetName "space-app-list" | Where-Object { $_.'アプリ名' })
    $baseAclRows = @(Read-KintoneExcelRows -Path $baseTemplatePath -WorksheetName "space-app-acl")
    $baseRecordAclRows = @(Read-KintoneExcelRows -Path $baseTemplatePath -WorksheetName "space-app-record-acl")

    if ($customTemplatePath) {
        $customSpaceRow = Read-KintoneExcelRows -Path $customTemplatePath -WorksheetName "space-settings" | Select-Object -First 1
        $customMemberRows = @(Read-KintoneExcelRows -Path $customTemplatePath -WorksheetName "space-member-list")
        $customAppRows = @(Read-KintoneExcelRows -Path $customTemplatePath -WorksheetName "space-app-list" | Where-Object { $_.'アプリ名' })
        $customAclRows = @(Read-KintoneExcelRows -Path $customTemplatePath -WorksheetName "space-app-acl")
        $customRecordAclRows = @(Read-KintoneExcelRows -Path $customTemplatePath -WorksheetName "space-app-record-acl")
    } else {
        $customSpaceRow = $null
        $customMemberRows = @()
        $customAppRows = @()
        $customAclRows = @()
        $customRecordAclRows = @()
    }

    $downloadSpaceRow = Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-settings" | Select-Object -First 1
    $downloadAppRows = @(Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-list" | Where-Object { $_.'アプリID' })
    $downloadAclRows = @(Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-acl")
    $downloadRecordAclRows = @(Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-record-acl")

    if (-not $baseSpaceRow -or -not $downloadSpaceRow) {
        Write-Message "テンプレートまたはダウンロード結果のspace-settingsが空です" -ForegroundColor Red -Type "Info" -NoHeader
        $script:exitCode = 1
        return
    }
    $newSpaceId = $downloadSpaceRow.'スペースID'

    # space-settings: 項目ごとにcustomの値があれば優先し、無ければbaseの値を使う
    $templateSpaceRow = [PSCustomObject]@{
        'スペース名'                                                      = Get-PreferredValue $customSpaceRow.'スペース名' $baseSpaceRow.'スペース名'
        '参加メンバーだけにこのスペースを公開する'                       = Get-PreferredValue $customSpaceRow.'参加メンバーだけにこのスペースを公開する' $baseSpaceRow.'参加メンバーだけにこのスペースを公開する'
        'スペースのポータルと複数のスレッドを使用する'                   = Get-PreferredValue $customSpaceRow.'スペースのポータルと複数のスレッドを使用する' $baseSpaceRow.'スペースのポータルと複数のスレッドを使用する'
        'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する' = Get-PreferredValue $customSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する' $baseSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する'
        'アプリ作成できるユーザーをスペースの管理者に限定する'           = Get-PreferredValue $customSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する' $baseSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する'
    }

    # スペース名はテンプレート（base/custom）のspace-settingsに列があればそれを優先し、無ければダウンロード結果（新スペースの現在の名前）を使う
    $spaceNameSource = if ("$($templateSpaceRow.'スペース名')" -ne "") { $templateSpaceRow.'スペース名' } else { $downloadSpaceRow.'スペース名' }
    $finalSpaceName = Expand-KintonePlaceholder -Value $spaceNameSource -ConfigName $DownloadConfigName

    # space-member-list: base・custom両方の行を残し、種別+ユーザー/組織/グループが重複する場合はcustomで上書きする
    $templateMemberRows = @(Merge-KintoneRowsByKey -BaseRows $baseMemberRows -CustomRows $customMemberRows -KeyProperties @("種別", "ユーザー/組織/グループ"))

    # space-app-list: base・custom双方を個別にダウンロード結果とマッチングし、ダウンロード先アプリIDを軸に統合する。
    # ACLはbase・custom両方のテンプレートアプリ名から取得するため、統合後も両方のテンプレートアプリ名を保持しておく
    $baseAppMapping = Get-AppNameMapping -TemplateApps $baseAppRows -DownloadApps $downloadAppRows
    $customAppMapping = if ($customAppRows.Count -gt 0) { Get-AppNameMapping -TemplateApps $customAppRows -DownloadApps $downloadAppRows } else { @() }

    $matchedByDownloadId = @{}
    foreach ($m in ($baseAppMapping | Where-Object { $_.DownloadAppId })) {
        $matchedByDownloadId[$m.DownloadAppId] = [PSCustomObject]@{
            DownloadAppId         = $m.DownloadAppId
            DownloadAppName       = $m.DownloadAppName
            BaseTemplateAppName   = $m.TemplateAppName
            CustomTemplateAppName = $null
        }
    }
    foreach ($m in ($customAppMapping | Where-Object { $_.DownloadAppId })) {
        if ($matchedByDownloadId.ContainsKey($m.DownloadAppId)) {
            $matchedByDownloadId[$m.DownloadAppId].CustomTemplateAppName = $m.TemplateAppName
        } else {
            $matchedByDownloadId[$m.DownloadAppId] = [PSCustomObject]@{
                DownloadAppId         = $m.DownloadAppId
                DownloadAppName       = $m.DownloadAppName
                BaseTemplateAppName   = $null
                CustomTemplateAppName = $m.TemplateAppName
            }
        }
    }

    # TemplateAppNameは対応付けの表示・ACL検索の代表名（customを優先）。DownloadAppNameは対応付けに使った
    # 元の名前として残すため、{PH}置き換え後の名前は別プロパティ（FinalAppName）に持たせる
    $matchedApps = @($matchedByDownloadId.Values | ForEach-Object {
        $finalTemplateAppName = if ($_.CustomTemplateAppName) { $_.CustomTemplateAppName } else { $_.BaseTemplateAppName }
        $finalAppName = Expand-KintonePlaceholder -Value $finalTemplateAppName -ConfigName $DownloadConfigName
        $_ | Add-Member -NotePropertyName "TemplateAppName" -NotePropertyValue $finalTemplateAppName -PassThru |
             Add-Member -NotePropertyName "FinalAppName" -NotePropertyValue $finalAppName -PassThru
    })

    $unmatchedBaseTemplateApps = @($baseAppMapping | Where-Object { $_.Status -ne "対応" -and $_.TemplateAppName })
    $unmatchedCustomTemplateApps = @($customAppMapping | Where-Object { $_.Status -ne "対応" -and $_.TemplateAppName })
    $unmatchedDownloadApps = @($downloadAppRows | Where-Object { -not $matchedByDownloadId.ContainsKey($_.'アプリID') })
    $hasUnmatched = ($unmatchedBaseTemplateApps.Count -gt 0) -or ($unmatchedCustomTemplateApps.Count -gt 0) -or ($unmatchedDownloadApps.Count -gt 0)

    if ($hasUnmatched) {
        Write-Message "" -Type "Info" -NoHeader
        Write-Message "## アプリの対応付けで確認が必要な項目" -Type "Info" -NoHeader
        foreach ($m in $unmatchedBaseTemplateApps) {
            Write-Message "  設定テンプレート（基本）のアプリ[$($m.TemplateAppName)]に対応する新スペースのアプリが見つかりません" -ForegroundColor Yellow -Type "Info" -NoHeader
        }
        foreach ($m in $unmatchedCustomTemplateApps) {
            Write-Message "  設定テンプレート（カスタム）のアプリ[$($m.TemplateAppName)]に対応する新スペースのアプリが見つかりません" -ForegroundColor Yellow -Type "Info" -NoHeader
        }
        foreach ($m in $unmatchedDownloadApps) {
            Write-Message "  新スペースのアプリ[$($m.'アプリ名')](appId=$($m.'アプリID'))に対応するテンプレートのアプリが見つかりません" -ForegroundColor Yellow -Type "Info" -NoHeader
        }
    }

    # space-settings: スペース名はテンプレート側に列があればそれを、無ければ新スペース側の値を使う。それ以外はテンプレート側の値を使う
    $outSpaceRow = [PSCustomObject]@{
        "スペースID"                                                     = $newSpaceId
        "スペース名"                                                     = $finalSpaceName
        "参加メンバーだけにこのスペースを公開する"                       = $templateSpaceRow.'参加メンバーだけにこのスペースを公開する'
        "スペースのポータルと複数のスレッドを使用する"                   = $templateSpaceRow.'スペースのポータルと複数のスレッドを使用する'
        "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する" = $templateSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する'
        "アプリ作成できるユーザーをスペースの管理者に限定する"           = $templateSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する'
    }
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-settings" -Rows @($outSpaceRow) -Headers @("スペースID", "スペース名", "参加メンバーだけにこのスペースを公開する", "スペースのポータルと複数のスレッドを使用する", "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する", "アプリ作成できるユーザーをスペースの管理者に限定する")
    Write-Message "" -Type "Info" -NoHeader
    Write-Message "# スペースID: $newSpaceId ($finalSpaceName)" -Type "Info" -NoHeader
    Write-ApplyStepResult -ActionLabel "スペース名を設定しました" -DetailLines @("　$finalSpaceName")
    $spaceRightLines = @('参加メンバーだけにこのスペースを公開する', 'スペースのポータルと複数のスレッドを使用する', 'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する', 'アプリ作成できるユーザーをスペースの管理者に限定する') | ForEach-Object {
        "　${_}: $($outSpaceRow.$_)"
    }
    Write-ApplyStepResult -ActionLabel "スペース権限を設定しました" -DetailLines $spaceRightLines

    # テンプレートに無い既存メンバー（スペース作成時にkintoneが自動追加する個人ユーザーなど）は
    # ダウンロード結果から引き継ぐ。apply側のSet-SpaceMembersはシートに無いコードのメンバーを
    # 消さずに残す設計のため、ここで引き継いでおかないとcheckで「想定外」と誤検知される
    $downloadMemberRows = @(Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-member-list")
    $templateMemberCodes = @($templateMemberRows | ForEach-Object { $_.'ユーザー/組織/グループ' })
    $keptMemberRows = @($downloadMemberRows | Where-Object { $templateMemberCodes -notcontains $_.'ユーザー/組織/グループ' })

    $outMemberRows = @($templateMemberRows | ForEach-Object {
        [PSCustomObject]@{
            "スペースID"             = $newSpaceId
            "種別"                   = $_.'種別'
            "ユーザー/組織/グループ" = $_.'ユーザー/組織/グループ'
            "管理者"                 = $_.'管理者'
            "下位組織も含める"       = $_.'下位組織も含める'
        }
    }) + @($keptMemberRows | ForEach-Object {
        [PSCustomObject]@{
            "スペースID"             = $newSpaceId
            "種別"                   = $_.'種別'
            "ユーザー/組織/グループ" = $_.'ユーザー/組織/グループ'
            "管理者"                 = $_.'管理者'
            "下位組織も含める"       = $_.'下位組織も含める'
        }
    })
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-member-list" -Rows $outMemberRows -Headers @("スペースID", "種別", "ユーザー/組織/グループ", "管理者", "下位組織も含める")
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
        $memberDetailLines += "  テンプレート外のメンバー ($($keptMemberRows.Count)件)"
        $memberDetailLines += @($keptMemberRows | ForEach-Object {
            $row = $_
            $flags = @('管理者', '下位組織も含める') | Where-Object { ToBool $row.$_ }
            "　　$($row.'種別'):$($row.'ユーザー/組織/グループ') - $($flags -join ',')"
        })
    }
    Write-ApplyStepResult -ActionLabel "スペースメンバーを設定しました" -CountPhrase "$($outMemberRows.Count)件" -DetailLines $memberDetailLines

    $outAppRows = @($matchedApps | ForEach-Object {
        [PSCustomObject]@{ "アプリID" = $_.DownloadAppId; "アプリ名" = $_.FinalAppName }
    })
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-app-list" -Rows $outAppRows -Headers @("アプリID", "アプリ名")

    $outAclRows = New-Object System.Collections.Generic.List[psobject]
    $aclRowSources = New-Object System.Collections.Generic.List[psobject]
    $outRecordAclRows = New-Object System.Collections.Generic.List[psobject]
    $recordAclRowSources = New-Object System.Collections.Generic.List[psobject]

    foreach ($m in $matchedApps) {
        Write-Message "" -Type "Info" -NoHeader
        Write-Message "## アプリID: $($m.DownloadAppId) ($($m.FinalAppName)) ===" -Type "Info" -NoHeader

        Write-ApplyStepResult -ActionLabel "アプリ名を設定しました" -DetailLines @("　$($m.FinalAppName)")

        $baseAclRowsForApp = if ($m.BaseTemplateAppName) { @($baseAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.BaseTemplateAppName)" }) } else { @() }
        $customAclRowsForApp = if ($m.CustomTemplateAppName) { @($customAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.CustomTemplateAppName)" }) } else { @() }
        $aclRows = @(Merge-KintoneRowsByKey -BaseRows $baseAclRowsForApp -CustomRows $customAclRowsForApp -KeyProperties @("種別", "ユーザー／組織／グループ"))
        $aclTargetLines = @($aclRows | ForEach-Object {
            $row = $_
            $grantedRights = @('レコード閲覧', 'レコード追加', 'レコード編集', 'レコード削除', 'アプリ管理', 'ファイル読み込み', 'ファイル書き出し') | Where-Object { ToBool $row.$_ }
            "　$($row.'種別'):$($row.'ユーザー／組織／グループ') - $($grantedRights -join ',')"
        })
        foreach ($r in $aclRows) {
            $outAclRows.Add([PSCustomObject]@{
                "アプリID"         = $m.DownloadAppId
                "アプリ名"         = $m.FinalAppName
                "種別"             = $r.'種別'
                "ユーザー／組織／グループ" = $r.'ユーザー／組織／グループ'
                "レコード閲覧"     = $r.'レコード閲覧'
                "レコード追加"     = $r.'レコード追加'
                "レコード編集"     = $r.'レコード編集'
                "レコード削除"     = $r.'レコード削除'
                "アプリ管理"       = $r.'アプリ管理'
                "ファイル読み込み" = $r.'ファイル読み込み'
                "ファイル書き出し" = $r.'ファイル書き出し'
            })
            $aclRowSources.Add([PSCustomObject]@{ DownloadAppName = $m.DownloadAppName; TemplateRow = $r })
        }
        Write-ApplyStepResult -ActionLabel "アプリの権限を設定しました" -CountPhrase "$($aclRows.Count)件" -DetailLines $aclTargetLines

        $baseRecordAclRowsForApp = if ($m.BaseTemplateAppName) { @($baseRecordAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.BaseTemplateAppName)" }) } else { @() }
        $customRecordAclRowsForApp = if ($m.CustomTemplateAppName) { @($customRecordAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.CustomTemplateAppName)" }) } else { @() }
        $recordAclRows = @(Merge-KintoneRowsByKey -BaseRows $baseRecordAclRowsForApp -CustomRows $customRecordAclRowsForApp -KeyProperties @("レコードの条件", "種別", "ユーザー／組織／グループ"))
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
                "アプリID"                 = $m.DownloadAppId
                "アプリ名"                 = $m.FinalAppName
                "レコードの条件"           = $r.'レコードの条件'
                "種別"                     = $r.'種別'
                "ユーザー／組織／グループ" = $r.'ユーザー／組織／グループ'
                "閲覧"                     = $r.'閲覧'
                "編集"                     = $r.'編集'
                "削除"                     = $r.'削除'
            })
            $recordAclRowSources.Add([PSCustomObject]@{ DownloadAppName = $m.DownloadAppName; TemplateRow = $r })
        }
        Write-ApplyStepResult -ActionLabel "アプリのレコード権限を設定しました" -CountPhrase "条件$($recordAclCondGroups.Count)件、対象$($recordAclRows.Count)件" -DetailLines $recordAclTargetLines
    }

    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-app-acl" -Rows $outAclRows.ToArray() -Headers @("アプリID", "アプリ名", "種別", "ユーザー／組織／グループ", "レコード閲覧", "レコード追加", "レコード編集", "レコード削除", "アプリ管理", "ファイル読み込み", "ファイル書き出し")
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-app-record-acl" -Rows $outRecordAclRows.ToArray() -Headers @("アプリID", "アプリ名", "レコードの条件", "種別", "ユーザー／組織／グループ", "閲覧", "編集", "削除")

    Set-KintoneHeaderRowColor -Path $outputPath -WorksheetNames @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl") -Color ([System.Drawing.Color]::FromArgb(217, 217, 217))

    $applyDiffColoring = $true # 赤字処理を一旦無効化

    # スペース名・アプリ名は{PH}置き換え部分だけを赤字にする。
    # それ以外は、ユニークキーでダウンロード結果に対応する行がある場合は値が異なるセルだけを赤字にし、
    # 対応する行が無い（新規追加）場合は行全体を赤字にする。ユニークキーは以下:
    #   space-settings: なし（1行のみ）
    #   space-member-list: 種別, ユーザー/組織/グループ
    #   space-app-list: アプリ名（マッチング済みのアプリのみ出力するため常に対応行あり）
    #   space-app-acl: アプリ名, 種別, ユーザー／組織／グループ
    #   space-app-record-acl: アプリ名, レコードの条件, 種別, ユーザー／組織／グループ
    $diffColor = [System.Drawing.Color]::FromArgb(255, 0, 0)
    $pkg = Open-ExcelPackage -Path $outputPath

    function Set-KintoneCellDiffColor {
        param($Cell, [string]$DownloadValue, [string]$FinalValue)
        if ($DownloadValue -eq $FinalValue) { return }
        $Cell.Style.Font.Color.SetColor($diffColor)
        $Cell.Style.Font.Bold = $true
    }

    if ($applyDiffColoring) {
        $wsSettings = $pkg.Workbook.Worksheets["space-settings"]
        Set-KintonePlaceholderRichText -Cell $wsSettings.Cells[2, 2] -OriginalValue $spaceNameSource -ConfigName $DownloadConfigName -Color $diffColor
        Set-KintoneCellDiffColor -Cell $wsSettings.Cells[2, 3] -DownloadValue "$($downloadSpaceRow.'参加メンバーだけにこのスペースを公開する')" -FinalValue "$($templateSpaceRow.'参加メンバーだけにこのスペースを公開する')"
        Set-KintoneCellDiffColor -Cell $wsSettings.Cells[2, 4] -DownloadValue "$($downloadSpaceRow.'スペースのポータルと複数のスレッドを使用する')" -FinalValue "$($templateSpaceRow.'スペースのポータルと複数のスレッドを使用する')"
        Set-KintoneCellDiffColor -Cell $wsSettings.Cells[2, 5] -DownloadValue "$($downloadSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する')" -FinalValue "$($templateSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する')"
        Set-KintoneCellDiffColor -Cell $wsSettings.Cells[2, 6] -DownloadValue "$($downloadSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')" -FinalValue "$($templateSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')"

        $wsAppList = $pkg.Workbook.Worksheets["space-app-list"]
        for ($i = 0; $i -lt $matchedApps.Count; $i++) {
            Set-KintonePlaceholderRichText -Cell $wsAppList.Cells[($i + 2), 2] -OriginalValue $matchedApps[$i].TemplateAppName -ConfigName $DownloadConfigName -Color $diffColor
        }

        $wsMember = $pkg.Workbook.Worksheets["space-member-list"]
        if ($wsMember -and $wsMember.Dimension) {
            $templateRowEnd = [Math]::Min(1 + $templateMemberRows.Count, $wsMember.Dimension.End.Row)
            for ($row = 2; $row -le $templateRowEnd; $row++) {
                $tmplRow = $templateMemberRows[$row - 2]
                # ユニークキー: 種別 + ユーザー/組織/グループ
                $dlRow = $downloadMemberRows | Where-Object {
                    "$($_.'種別')" -eq "$($tmplRow.'種別')" -and
                    "$($_.'ユーザー/組織/グループ')" -eq "$($tmplRow.'ユーザー/組織/グループ')"
                } | Select-Object -First 1
                if (-not $dlRow) {
                    for ($col = 1; $col -le $wsMember.Dimension.End.Column; $col++) {
                        $wsMember.Cells[$row, $col].Style.Font.Color.SetColor($diffColor)
                        $wsMember.Cells[$row, $col].Style.Font.Bold = $true
                    }
                    continue
                }
                Set-KintoneCellDiffColor -Cell $wsMember.Cells[$row, 4] -DownloadValue "$($dlRow.'管理者')" -FinalValue "$($tmplRow.'管理者')"
                Set-KintoneCellDiffColor -Cell $wsMember.Cells[$row, 5] -DownloadValue "$($dlRow.'下位組織も含める')" -FinalValue "$($tmplRow.'下位組織も含める')"
            }
        }

        $wsAcl = $pkg.Workbook.Worksheets["space-app-acl"]
        if ($wsAcl -and $wsAcl.Dimension) {
            for ($i = 0; $i -lt $aclRowSources.Count; $i++) {
                $row = $i + 2
                if ($row -gt $wsAcl.Dimension.End.Row) { break }
                $src = $aclRowSources[$i]
                $tmplRow = $src.TemplateRow
                # ユニークキー: アプリ名 + 種別 + ユーザー／組織／グループ
                $dlRow = $downloadAclRows | Where-Object {
                    "$($_.'アプリ名')" -eq "$($src.DownloadAppName)" -and
                    "$($_.'種別')" -eq "$($tmplRow.'種別')" -and
                    "$($_.'ユーザー／組織／グループ')" -eq "$($tmplRow.'ユーザー／組織／グループ')"
                } | Select-Object -First 1
                if (-not $dlRow) {
                    for ($col = 1; $col -le $wsAcl.Dimension.End.Column; $col++) {
                        $wsAcl.Cells[$row, $col].Style.Font.Color.SetColor($diffColor)
                        $wsAcl.Cells[$row, $col].Style.Font.Bold = $true
                    }
                    continue
                }
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 5] -DownloadValue "$($dlRow.'レコード閲覧')" -FinalValue "$($tmplRow.'レコード閲覧')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 6] -DownloadValue "$($dlRow.'レコード追加')" -FinalValue "$($tmplRow.'レコード追加')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 7] -DownloadValue "$($dlRow.'レコード編集')" -FinalValue "$($tmplRow.'レコード編集')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 8] -DownloadValue "$($dlRow.'レコード削除')" -FinalValue "$($tmplRow.'レコード削除')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 9] -DownloadValue "$($dlRow.'アプリ管理')" -FinalValue "$($tmplRow.'アプリ管理')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 10] -DownloadValue "$($dlRow.'ファイル読み込み')" -FinalValue "$($tmplRow.'ファイル読み込み')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 11] -DownloadValue "$($dlRow.'ファイル書き出し')" -FinalValue "$($tmplRow.'ファイル書き出し')"
            }
        }

        $wsRecordAcl = $pkg.Workbook.Worksheets["space-app-record-acl"]
        if ($wsRecordAcl -and $wsRecordAcl.Dimension) {
            for ($i = 0; $i -lt $recordAclRowSources.Count; $i++) {
                $row = $i + 2
                if ($row -gt $wsRecordAcl.Dimension.End.Row) { break }
                $src = $recordAclRowSources[$i]
                $tmplRow = $src.TemplateRow
                # ユニークキー: アプリ名 + レコードの条件 + 種別 + ユーザー／組織／グループ
                $dlRow = $downloadRecordAclRows | Where-Object {
                    "$($_.'アプリ名')" -eq "$($src.DownloadAppName)" -and
                    "$($_.'レコードの条件')" -eq "$($tmplRow.'レコードの条件')" -and
                    "$($_.'種別')" -eq "$($tmplRow.'種別')" -and
                    "$($_.'ユーザー／組織／グループ')" -eq "$($tmplRow.'ユーザー／組織／グループ')"
                } | Select-Object -First 1
                if (-not $dlRow) {
                    for ($col = 1; $col -le $wsRecordAcl.Dimension.End.Column; $col++) {
                        $wsRecordAcl.Cells[$row, $col].Style.Font.Color.SetColor($diffColor)
                        $wsRecordAcl.Cells[$row, $col].Style.Font.Bold = $true
                    }
                    continue
                }
                Set-KintoneCellDiffColor -Cell $wsRecordAcl.Cells[$row, 6] -DownloadValue "$($dlRow.'閲覧')" -FinalValue "$($tmplRow.'閲覧')"
                Set-KintoneCellDiffColor -Cell $wsRecordAcl.Cells[$row, 7] -DownloadValue "$($dlRow.'編集')" -FinalValue "$($tmplRow.'編集')"
                Set-KintoneCellDiffColor -Cell $wsRecordAcl.Cells[$row, 8] -DownloadValue "$($dlRow.'削除')" -FinalValue "$($tmplRow.'削除')"
            }
        }
    }

    foreach ($sheetName in @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl")) {
        $ws = $pkg.Workbook.Worksheets[$sheetName]
        if (-not $ws) { continue }
        Set-KintoneColumnWidth -Worksheet $ws
    }

    Close-ExcelPackage $pkg

    Write-Message "" -Type "Info" -NoHeader
    Write-Message "設定内容を出力しました: $outputPath" -ForegroundColor Green -Type "Info" -NoHeader
    if ($hasUnmatched) {
        # 対応付け未了の警告のみで設定ファイル自体は生成済みのため、致命的エラー(exit 1)とは区別する
        $script:exitCode = 2
    }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Message "" -Type "Info" -NoHeader
Write-Message "ログを出力しました: $logFilePath" -ForegroundColor Green -Type "Info" -NoHeader
exit $script:exitCode
