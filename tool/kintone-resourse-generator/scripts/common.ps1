# =========================================
# kintoneリソース生成ツール 共通処理
# =========================================
# download-kintone-resources.ps1 / check-kintone-resources.ps1 / apply-kintone-resources.ps1 /
# generate-config-from-template.ps1 で共通して使う関数をまとめたもの。
# 各スクリプトの先頭でドットソース（. "パス\common.ps1"）して読み込む。

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# gui.ps1から起動された場合はcmd.exe経由の標準出力リダイレクトで色情報が失われるため、
# 行頭に色タグを埋め込んで渡す（gui.ps1側のWrite-Logで解釈して着色し直す）
function Write-Message {
    param(
        [string]$Text = "",
        [ConsoleColor]$ForegroundColor = "White"
    )
    if ($env:GUI_LOG_MODE -eq "1") {
        Write-Host "[[COLOR:$ForegroundColor]]$Text"
    } else {
        Write-Host $Text -ForegroundColor $ForegroundColor
    }
}

function New-KintoneLogPath {
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [Parameter(Mandatory)][string]$Prefix
    )
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    return Join-Path $LogRoot "${Prefix}_${timestamp}.log"
}

# Tee-Objectは-Encoding非対応で既定UTF-16LE書き込みになるため、事後にUTF-8へ変換する。
# GUI経由の実行ではWrite-Messageが行頭に[[COLOR:xxx]]タグを埋め込むため（gui.ps1のWrite-Log用）、
# ファイルに残るログはこのタグを取り除いたテキストにする。
function ConvertTo-Utf8LogFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $content = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $content) { $content = "" }
    $content = $content -replace '\[\[COLOR:\w+\]\]', ''
    [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding($true)))
}

function ToBool($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [bool]) { return $value }
    if ($value -is [string]) {
        if ($value -eq "") { return $null }
        switch ($value.ToLower()) {
            "true"  { return $true }
            "false" { return $false }
        }
    }
    return $false
}

function Get-KintoneAuthorizationHeader {
    param([string]$BaseUrl)

    if ($env:KINTONE_LOGIN -and $env:KINTONE_PASSWORD) {
        $login = $env:KINTONE_LOGIN
        $password = $env:KINTONE_PASSWORD
    } else {
        Write-Message "kintoneへログインします: $BaseUrl" -ForegroundColor Cyan
        $login = Read-Host "ログイン名"
        $securePassword = Read-Host "パスワード" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        try {
            $password = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    # スペーステンプレートからのスペース作成APIはmembers（管理者1名以上）が必須のため、
    # ログインユーザー自身を管理者として使えるようにscriptスコープに残しておく。
    $script:kintoneLogin = $login
    $pair = "${login}:${password}"
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
}

function Invoke-KintoneRequest {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        $Body = $null
    )

    $headers = @{ "X-Cybozu-Authorization" = $Authorization }
    $uri = "$BaseUrl$Path"

    try {
        if ($null -ne $Body) {
            $headers["Content-Type"] = "application/json; charset=utf-8"
            $json = $Body | ConvertTo-Json -Depth 10
            # -Bodyに文字列のまま渡すとWindows PowerShell 5.1では既定エンコーディングでマルチバイト
            # 文字（日本語）が "?" に化けて送信される。必ずUTF-8バイト配列に変換してから渡す。
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            return Invoke-RestMethod -Uri $uri -Headers $headers -Method $Method -Body $bytes
        } else {
            return Invoke-RestMethod -Uri $uri -Headers $headers -Method $Method
        }
    } catch {
        $detail = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        throw "kintone APIエラー ($Method $Path): $detail"
    }
}

function Build-KintoneArrayQuery {
    param(
        [Parameter(Mandatory)][string]$ParamName,
        [Parameter(Mandatory)][string[]]$Values
    )
    $parts = @()
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $parts += "$ParamName[$i]=$($Values[$i])"
    }
    return ($parts -join "&")
}

function Test-SheetSelected {
    param(
        [string[]]$SelectedSheets,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not $SelectedSheets -or $SelectedSheets.Count -eq 0) { return $true }
    return $SelectedSheets -contains $Name
}

function ConvertTo-SheetNameArray {
    param([string]$Sheets)
    if (-not $Sheets) { return @() }
    return @($Sheets.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# スペーステンプレート（kintone側で元スペースを「テンプレートとして保存」しておく必要がある。
# この保存操作自体はAPIには無くkintoneの管理画面のみ）から新しいスペースを作成する。
# kintoneのAPI仕様上、members（スペース管理者1名以上）を指定しないとエラーになるため、
# 呼び出し元のログインユーザーを唯一の管理者として設定する。
# 作成されたスペースIDを返す。
function New-KintoneSpaceFromTemplate {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$TemplateId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$AdminLogin
    )

    $body = @{
        id      = [int]$TemplateId
        name    = $Name
        members = @(
            @{ entity = @{ type = "USER"; code = $AdminLogin }; isAdmin = $true }
        )
    }

    $resp = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method POST -Path "/k/v1/template/space.json" -Body $body
    return $resp.id
}

function Get-CurrentSpace {
    param(
        [Parameter(Mandatory)][string]$SpaceId,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [bool]$HasAppAcl = $true,
        [bool]$HasRecordAcl = $true,
        [bool]$HasMember = $true
    )

    Write-Message "スペース取得 開始: $SpaceId"

    $space = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/space.json?id=$SpaceId"

    $apps = @($space.attachedApps | ForEach-Object {
        [PSCustomObject]@{
            appId        = $_.appId
            name         = $_.name
            rights       = @()
            recordRights = @()
        }
    })

    if ($HasAppAcl) {
        foreach ($app in $apps) {
            try {
                $acl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/app/acl.json?app=$($app.appId)"
                $app.rights = @($acl.rights)
            } catch {
                Write-Message "  アプリ[$($app.name)]のACL取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    if ($HasRecordAcl) {
        foreach ($app in $apps) {
            try {
                $recordAcl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/record/acl.json?app=$($app.appId)"
                $app.recordRights = @($recordAcl.rights)
            } catch {
                Write-Message "  アプリ[$($app.name)]のレコードACL取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    $members = @()
    if ($HasMember) {
        $memberResp = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/space/members.json?id=$SpaceId"
        $members = @($memberResp.members)
    }

    Write-Message "スペース取得 終了: $SpaceId"

    return [PSCustomObject]@{
        spaceId        = $space.id
        spaceName      = $space.name
        isPrivate      = $space.isPrivate
        useMultiThread = $space.useMultiThread
        fixedMember    = $space.fixedMember
        createApp      = $space.permissions.createApp
        apps           = $apps
        members        = $members
    }
}

function Get-AppCurrentInfo {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$AppId
    )

    $name = $null
    try {
        $settings = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/app/settings.json?app=$AppId"
        $name = $settings.name
    } catch {
        Write-Message "  アプリID[$AppId]の設定取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $rights = @()
    try {
        $acl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/app/acl.json?app=$AppId"
        $rights = @($acl.rights)
    } catch {
        Write-Message "  アプリID[$AppId]のACL取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $recordRights = @()
    try {
        $recordAcl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/record/acl.json?app=$AppId"
        $recordRights = @($recordAcl.rights)
    } catch {
        Write-Message "  アプリID[$AppId]のレコードACL取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return [PSCustomObject]@{
        appId        = $AppId
        name         = $name
        rights       = $rights
        recordRights = $recordRights
    }
}

function Set-Space {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$SpaceId,
        [string]$Name,
        $IsPrivate = $null,
        $UseMultiThread = $null,
        $FixedMember = $null,
        $CreateAppAdminOnly = $null
    )

    $body = @{ id = $SpaceId }
    if ($Name) { $body["name"] = $Name }
    if ($null -ne $IsPrivate) { $body["isPrivate"] = $IsPrivate }
    if ($null -ne $UseMultiThread) { $body["useMultiThread"] = $UseMultiThread }
    if ($null -ne $FixedMember) { $body["fixedMember"] = $FixedMember }
    if ($null -ne $CreateAppAdminOnly) {
        $body["permissions"] = @{ createApp = $(if ($CreateAppAdminOnly) { "ADMIN" } else { "EVERYONE" }) }
    }
    Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/space.json" -Body $body | Out-Null

    # スペース名を変更した場合、デフォルトスレッドの名前もスペース名と同じにする。
    if ($Name) {
        $space = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/space.json?id=$SpaceId"
        if ($space.defaultThread) {
            Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/space/thread.json" -Body @{ id = $space.defaultThread; name = $Name } | Out-Null
        }
    }
}

# space-member-listシートの「種別」列（組織/グループ/ユーザー）とkintoneのentity.typeを相互変換する。
# ラベルが空・未知の場合はGet-KintoneMemberTypeが$nullを返す（呼び出し側で自動判定にフォールバックする）。
function Get-KintoneMemberTypeLabel {
    param([string]$Type)
    switch ($Type) {
        "ORGANIZATION" { return "組織" }
        "GROUP"        { return "グループ" }
        "USER"         { return "ユーザー" }
        default        { return $Type }
    }
}

function Get-KintoneMemberType {
    param([string]$Label)
    switch ($Label) {
        "組織"     { return "ORGANIZATION" }
        "グループ" { return "GROUP" }
        "ユーザー" { return "USER" }
        default    { return $null }
    }
}

# 組織・グループ・ユーザーのコードは重複しない前提のため、コードだけから種別を自動判定する
# （kintoneのユーザーAPIで組織→グループ→ユーザーの順に検索し、最初に見つかった種別を返す）。
function Get-KintoneMemberEntityType {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$Code
    )

    $org = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/v1/organizations.json?codes[0]=$Code"
    if ($org.organizations.Count -gt 0) { return "ORGANIZATION" }

    $group = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/v1/groups.json?codes[0]=$Code"
    if ($group.groups.Count -gt 0) { return "GROUP" }

    $user = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/v1/users.json?codes[0]=$Code"
    if ($user.users.Count -gt 0) { return "USER" }

    throw "組織・グループ・ユーザーのいずれにも一致しないコードです: $Code"
}

# PUT /k/v1/space/members.jsonは送ったmembers配列で完全に置き換わる（実機で確認済み）。
# space-member-listシートに無いコードのメンバー（個人ユーザーなど、テンプレートで管理しないもの）を
# 消さないよう、現在のメンバーのうちシートに無いコードだけを残し、シートの内容を追加する。
function Set-SpaceMembers {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$SpaceId,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$MemberRows
    )

    $sheetCodes = @($MemberRows | ForEach-Object { $_.'ユーザー/組織/グループ' })

    $current = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/space/members.json?id=$SpaceId"
    $keptMembers = @($current.members | Where-Object { $sheetCodes -notcontains $_.entity.code } | ForEach-Object {
        @{
            entity      = @{ type = $_.entity.type; code = $_.entity.code }
            isAdmin     = [bool]$_.isAdmin
            includeSubs = if ($null -ne $_.includeSubs) { [bool]$_.includeSubs } else { $false }
        }
    })

    $newMembers = @($MemberRows | ForEach-Object {
        $code = $_.'ユーザー/組織/グループ'
        $type = Get-KintoneMemberType $_.'種別'
        if (-not $type) {
            $type = Get-KintoneMemberEntityType -BaseUrl $BaseUrl -Authorization $Authorization -Code $code
        }
        @{
            entity      = @{ type = $type; code = $code }
            isAdmin     = [bool](ToBool $_.'管理者')
            includeSubs = [bool](ToBool $_.'下位組織も含める')
        }
    })

    $body = @{ id = $SpaceId; members = @($keptMembers + $newMembers) }
    Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/space/members.json" -Body $body | Out-Null
}

function Set-AppName {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )

    $body = @{ app = $AppId; name = $Name }
    Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/preview/app/settings.json" -Body $body | Out-Null
}

# 「種別」列（組織/グループ/ユーザー/作成者）が指定されていればそれを使い、無ければコードから
# 自動判定する（Get-KintoneMemberEntityType）。-AllowCreatorを指定した場合のみ、コードが
# "作成者"であればCREATOR（レコード作成者、codeはnull）として扱う。
function Resolve-KintoneEntityType {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [string]$TypeLabel,
        [Parameter(Mandatory)][string]$Code,
        [switch]$AllowCreator
    )
    if ($AllowCreator -and $Code -eq "作成者") { return "CREATOR" }

    $type = Get-KintoneMemberType $TypeLabel
    if ($type) { return $type }
    return Get-KintoneMemberEntityType -BaseUrl $BaseUrl -Authorization $Authorization -Code $Code
}

function New-AppAclRightFromRow {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        $Row
    )

    $orgName = $Row.'ユーザー／組織／グループ'
    $entityType = Resolve-KintoneEntityType -BaseUrl $BaseUrl -Authorization $Authorization -TypeLabel $Row.'種別' -Code $orgName

    return @{
        entity            = @{ type = $entityType; code = $orgName }
        includeSubs       = $false
        appEditable       = [bool](ToBool $Row.'アプリ管理')
        recordViewable    = [bool](ToBool $Row.'レコード閲覧')
        recordAddable     = [bool](ToBool $Row.'レコード追加')
        recordEditable    = [bool](ToBool $Row.'レコード編集')
        recordDeletable   = [bool](ToBool $Row.'レコード削除')
        recordImportable  = [bool](ToBool $Row.'ファイル読み込み')
        recordExportable  = [bool](ToBool $Row.'ファイル書き出し')
    }
}

# kintoneはrightsにCREATOR(appEditable:true)相当が無いとCB_NO04エラーになるため自動的に補う。
function Set-AppAcl {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][array]$Rights
    )

    $hasCreatorManage = [bool]($Rights | Where-Object { $_.entity.type -eq "CREATOR" -and $_.appEditable })

    $finalRights = @()
    if (-not $hasCreatorManage) {
        $finalRights += @{
            entity           = @{ type = "CREATOR"; code = $null }
            includeSubs      = $false
            appEditable      = $true
            recordViewable   = $true
            recordAddable    = $true
            recordEditable   = $true
            recordDeletable  = $true
            recordImportable = $true
            recordExportable = $true
        }
    }
    $finalRights += $Rights

    $body = @{ app = $AppId; rights = $finalRights }
    Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/preview/app/acl.json" -Body $body | Out-Null
}

# レコードの条件列はkintoneのクエリ記法そのままの値として無変換で渡す。
function New-RecordAclRightsFromRows {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][array]$Rows
    )

    $rights = @()
    foreach ($condGroup in ($Rows | Group-Object -Property 'レコードの条件')) {
        $entities = @($condGroup.Group | ForEach-Object {
            $orgName = $_.'ユーザー／組織／グループ'
            $entityType = Resolve-KintoneEntityType -BaseUrl $BaseUrl -Authorization $Authorization -TypeLabel $_.'種別' -Code $orgName -AllowCreator
            # アクセス権の継承（下位組織も含める）は組織種別にしか意味を持たないため、
            # 組織以外（グループ・ユーザー・作成者）は常にfalseで送る。
            $includeSubs = if ($entityType -eq "ORGANIZATION") { [bool](ToBool $_.'アクセス権の継承') } else { $false }
            @{
                entity      = @{ type = $entityType; code = $(if ($entityType -eq "CREATOR") { $null } else { $orgName }) }
                viewable    = [bool](ToBool $_.'閲覧')
                editable    = [bool](ToBool $_.'編集')
                deletable   = [bool](ToBool $_.'削除')
                includeSubs = $includeSubs
            }
        })
        $rights += @{
            filterCond = "$($condGroup.Name)"
            entities   = $entities
        }
    }
    # 要素数1件だとPowerShellのパイプライン展開で配列が単一Hashtableに潰れるため、単項カンマで防ぐ。
    return ,$rights
}

function Set-AppRecordAcl {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][array]$Rights
    )

    $body = @{ app = $AppId; rights = $Rights }
    Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/preview/record/acl.json" -Body $body | Out-Null
}

function Update-KintoneApps {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string[]]$AppIds,
        [int]$TimeoutSeconds = 120
    )

    $uniqueIds = @($AppIds | Select-Object -Unique)
    if ($uniqueIds.Count -eq 0) { return }

    Write-Message "アプリの更新開始: $($uniqueIds -join ', ')"

    $body = @{ apps = @($uniqueIds | ForEach-Object { @{ app = $_ } }) }
    Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method POST -Path "/k/v1/preview/app/deploy.json" -Body $body | Out-Null

    $query = Build-KintoneArrayQuery -ParamName "apps" -Values $uniqueIds
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ($true) {
        Start-Sleep -Seconds 2
        $resp = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/preview/app/deploy.json?$query"
        $pending = @($resp.apps | Where-Object { $_.status -eq "PROCESSING" })
        if ($pending.Count -eq 0) {
            $failed = @($resp.apps | Where-Object { $_.status -ne "SUCCESS" })
            if ($failed.Count -gt 0) {
                throw "更新に失敗したアプリがあります: $($failed | ConvertTo-Json -Compress)"
            }
            Write-Message "アプリの更新完了: $($uniqueIds -join ', ')"
            return
        }
        if ((Get-Date) -gt $deadline) {
            throw "更新がタイムアウトしました(${TimeoutSeconds}秒): $($resp.apps | ConvertTo-Json -Compress)"
        }
    }
}

function Read-KintoneExcelRows {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$WorksheetName
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Excelファイルが見つかりません: $Path"
    }
    return Import-Excel -Path $Path -WorksheetName $WorksheetName
}

function Write-KintoneExcelRows {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$WorksheetName,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Rows,
        [string[]]$Headers = @()
    )

    New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null

    $rowsToWrite = $Rows
    if ($rowsToWrite.Count -eq 0) {
        if ($Headers.Count -eq 0) {
            Write-Message "  (書き込み対象の行が無いためスキップ: $Path [$WorksheetName])" -ForegroundColor Yellow
            return
        }
        $blank = [ordered]@{}
        foreach ($h in $Headers) { $blank[$h] = $null }
        $rowsToWrite = @([PSCustomObject]$blank)
    }

    $rowsToWrite | Export-Excel -Path $Path -WorksheetName $WorksheetName -ClearSheet -AutoSize
}

function Group-RowsBySpaceId {
    param([Parameter(Mandatory)][array]$Rows)
    return $Rows | Group-Object -Property 'スペースID'
}

# ダウンロード結果のスペース名・アプリ名に含まれる "{PH}" を、そのconfig名に置き換える。
# kintone側でスペース・アプリを作成する時点では最終的な名前が決まらないため、
# 仮の名前として"{PH}"を埋め込んでおき、generate-config-from-template実行時に確定させる用途。
function Expand-KintonePlaceholder {
    param([string]$Value, [Parameter(Mandatory)][string]$ConfigName)
    if (-not $Value) { return $Value }
    return $Value.Replace('{PH}', $ConfigName)
}

# "{PH}"を含む元の値を基準に、{PH}だった部分だけ色を変えたリッチテキストをセルに設定する
# （置き換わった文字だけ見分けられるように）。{PH}を含まない場合は何もしない。
function Set-KintonePlaceholderRichText {
    param(
        [Parameter(Mandatory)]$Cell,
        [string]$OriginalValue,
        [Parameter(Mandatory)][string]$ConfigName,
        [Parameter(Mandatory)][System.Drawing.Color]$Color
    )
    if (-not $OriginalValue -or -not $OriginalValue.Contains('{PH}')) { return }

    $segments = $OriginalValue.Split([string[]]@('{PH}'), [System.StringSplitOptions]::None)
    $Cell.Value = $null
    for ($i = 0; $i -lt $segments.Length; $i++) {
        if ($segments[$i]) { $Cell.RichText.Add($segments[$i]) | Out-Null }
        if ($i -lt $segments.Length - 1) {
            $run = $Cell.RichText.Add($ConfigName)
            $run.Color = $Color
            $run.Bold = $true
        }
    }
}

# アプリ名は毎回、共通の一部に対して前後（プレフィックス/サフィックス）が付き足される形でしか
# 変化しない前提のため、「どちらかがどちらかを含むか」の2択で一致判定する（1=一致/0=不一致）。
function Get-AppNameSimilarity {
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return 0.0 }
    if ($A.Contains($B) -or $B.Contains($A)) { return 1.0 }
    return 0.0
}

# テンプレート側アプリ（アプリ名のみ、IDは持たない）と新スペース側アプリを、
# アプリ名の一致（どちらかがどちらかを含む）で1対1に対応付ける。
# 一致するペアが複数のアプリにまたがって重複した場合は、先に確定したペアを優先する。
# 対応関係は配列のインデックスで管理する（アプリ名をキーにすると、同名のアプリが
# 複数あった場合に片方の対応付けでもう片方まで「対応済み」扱いになり、
# 結果から消えてしまうため）。
function Get-AppNameMapping {
    param(
        [Parameter(Mandatory)][array]$TemplateApps,
        [Parameter(Mandatory)][array]$DownloadApps
    )

    $candidates = New-Object System.Collections.Generic.List[psobject]
    for ($ti = 0; $ti -lt $TemplateApps.Count; $ti++) {
        for ($di = 0; $di -lt $DownloadApps.Count; $di++) {
            $similarity = Get-AppNameSimilarity -A "$($TemplateApps[$ti].'アプリ名')" -B "$($DownloadApps[$di].'アプリ名')"
            $candidates.Add([PSCustomObject]@{ TemplateIndex = $ti; DownloadIndex = $di; Similarity = $similarity })
        }
    }

    $usedTemplateIndexes = @{}
    $usedDownloadIndexes = @{}
    $result = New-Object System.Collections.Generic.List[psobject]

    foreach ($c in ($candidates | Sort-Object -Property Similarity -Descending)) {
        if ($usedTemplateIndexes.ContainsKey($c.TemplateIndex) -or $usedDownloadIndexes.ContainsKey($c.DownloadIndex)) { continue }
        if ($c.Similarity -eq 0) { continue }
        $usedTemplateIndexes[$c.TemplateIndex] = $true
        $usedDownloadIndexes[$c.DownloadIndex] = $true
        $result.Add([PSCustomObject]@{
            TemplateAppName = $TemplateApps[$c.TemplateIndex].'アプリ名'
            DownloadAppId   = $DownloadApps[$c.DownloadIndex].'アプリID'
            DownloadAppName = $DownloadApps[$c.DownloadIndex].'アプリ名'
            Status          = "対応"
        })
    }

    for ($ti = 0; $ti -lt $TemplateApps.Count; $ti++) {
        if ($usedTemplateIndexes.ContainsKey($ti)) { continue }
        $result.Add([PSCustomObject]@{
            TemplateAppName = $TemplateApps[$ti].'アプリ名'
            DownloadAppId   = $null
            DownloadAppName = $null
            Status          = "対応なし（新スペース側に見つかりません）"
        })
    }
    for ($di = 0; $di -lt $DownloadApps.Count; $di++) {
        if ($usedDownloadIndexes.ContainsKey($di)) { continue }
        $result.Add([PSCustomObject]@{
            TemplateAppName = $null
            DownloadAppId   = $DownloadApps[$di].'アプリID'
            DownloadAppName = $DownloadApps[$di].'アプリ名'
            Status          = "対応なし（テンプレート側に見つかりません）"
        })
    }
    return $result
}

function Set-KintoneHeaderRowColor {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$WorksheetNames,
        [Parameter(Mandatory)][System.Drawing.Color]$Color
    )

    $pkg = Open-ExcelPackage -Path $Path
    foreach ($sheetName in $WorksheetNames) {
        $ws = $pkg.Workbook.Worksheets[$sheetName]
        if (-not $ws -or -not $ws.Dimension) { continue }
        $lastCol = $ws.Dimension.End.Column
        for ($c = 1; $c -le $lastCol; $c++) {
            $cell = $ws.Cells[1, $c]
            $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $cell.Style.Fill.BackgroundColor.SetColor($Color)
        }
        Set-KintoneColumnWidth -Worksheet $ws
    }
    Close-ExcelPackage $pkg
}

# 列の幅を内容に合わせて自動調整する。EPPlusのAutoFitColumnsは日本語（全角）文字の幅を
# 少し狭く見積もる傾向があるため、自動調整後に余白を追加して見切れを防ぐ。
function Set-KintoneColumnWidth {
    param([Parameter(Mandatory)]$Worksheet)
    if (-not $Worksheet.Dimension) { return }
    $Worksheet.Cells.AutoFitColumns()
    for ($c = 1; $c -le $Worksheet.Dimension.End.Column; $c++) {
        $Worksheet.Column($c).Width += 4
    }
}
