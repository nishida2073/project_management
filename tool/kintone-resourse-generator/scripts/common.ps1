# =========================================
# kintoneリソース生成ツール 共通処理
# =========================================
# download-kintone-resources.ps1 / check-kintone-resources.ps1 / apply-kintone-resources.ps1
# で共通して使う関数をまとめたもの。
# 各スクリプトの先頭でドットソース（. "パス\common.ps1"）して読み込む。

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

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
function ConvertTo-Utf8LogFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $content = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $content) { $content = "" }
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

# =========================================
# 認証・API呼び出し
# =========================================

function Get-KintoneAuthorizationHeader {
    param([string]$BaseUrl)

    if ($env:KINTONE_LOGIN -and $env:KINTONE_PASSWORD) {
        $login = $env:KINTONE_LOGIN
        $password = $env:KINTONE_PASSWORD
    } else {
        Write-Host "kintoneへログインします: $BaseUrl" -ForegroundColor Cyan
        $login = Read-Host "ログイン名"
        $securePassword = Read-Host "パスワード" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        try {
            $password = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
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

# =========================================
# スペース
# =========================================

function Get-CurrentSpace {
    param(
        [Parameter(Mandatory)][string]$SpaceId,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [bool]$HasAppAcl = $true,
        [bool]$HasRecordAcl = $true,
        [bool]$HasMember = $true
    )

    Write-Host "スペース取得 開始: $SpaceId"

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
                Write-Host "  アプリ[$($app.name)]のACL取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    if ($HasRecordAcl) {
        foreach ($app in $apps) {
            try {
                $recordAcl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/record/acl.json?app=$($app.appId)"
                $app.recordRights = @($recordAcl.rights)
            } catch {
                Write-Host "  アプリ[$($app.name)]のレコードACL取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    $members = @()
    if ($HasMember) {
        $memberResp = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/space/members.json?id=$SpaceId"
        $members = @($memberResp.members)
    }

    Write-Host "スペース取得 終了: $SpaceId"

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
        Write-Host "  アプリID[$AppId]の設定取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $rights = @()
    try {
        $acl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/app/acl.json?app=$AppId"
        $rights = @($acl.rights)
    } catch {
        Write-Host "  アプリID[$AppId]のACL取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $recordRights = @()
    try {
        $recordAcl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/record/acl.json?app=$AppId"
        $recordRights = @($recordAcl.rights)
    } catch {
        Write-Host "  アプリID[$AppId]のレコードACL取得に失敗: $($_.Exception.Message)" -ForegroundColor Yellow
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
}

# PUT /k/v1/space/members.jsonは送ったmembers配列で完全に置き換わる（実機で確認済み）。
# space-member-listシートはORGANIZATION種別しか持たないため、そのままPUTするとUSER/GROUPメンバーが
# 消える。現在のメンバーを取得し、ORGANIZATION以外を残した上でORGANIZATION分だけ置き換える。
function Set-SpaceMembers {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string]$SpaceId,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$MemberRows
    )

    $current = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/space/members.json?id=$SpaceId"
    $keptMembers = @($current.members | Where-Object { $_.entity.type -ne "ORGANIZATION" } | ForEach-Object {
        @{
            entity      = @{ type = $_.entity.type; code = $_.entity.code }
            isAdmin     = [bool]$_.isAdmin
            includeSubs = if ($null -ne $_.includeSubs) { [bool]$_.includeSubs } else { $false }
        }
    })

    $newOrgMembers = @($MemberRows | ForEach-Object {
        @{
            entity      = @{ type = "ORGANIZATION"; code = $_.'組織名' }
            isAdmin     = [bool](ToBool $_.'管理者')
            includeSubs = [bool](ToBool $_.'下位組織も含める')
        }
    })

    $body = @{ id = $SpaceId; members = @($keptMembers + $newOrgMembers) }
    Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/space/members.json" -Body $body | Out-Null
}

# =========================================
# アプリ
# =========================================

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

function Get-KintoneEntityType {
    param([string]$Name)
    switch ($Name) {
        "everyone" { return "GROUP" }
        "作成者"   { return "CREATOR" }
        default    { return "ORGANIZATION" }
    }
}

function New-AppAclRightFromRow {
    param($Row)

    $orgName = $Row.'組織名'
    $entityType = Get-KintoneEntityType -Name $orgName

    return @{
        entity            = @{ type = $entityType; code = $(if ($entityType -eq "CREATOR") { $null } else { $orgName }) }
        includeSubs       = $false
        appEditable       = [bool](ToBool $Row.'アプリ管理')
        recordViewable    = [bool](ToBool $Row.'レコード閲覧')
        recordAddable     = [bool](ToBool $Row.'レコード追加')
        recordEditable    = [bool](ToBool $Row.'レコード編集')
        recordDeletable   = [bool](ToBool $Row.'レコード削除')
        recordImportable  = [bool](ToBool $Row.'ファイル読み込み')
        recordExportable  = $false
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
    param([Parameter(Mandatory)][array]$Rows)

    $rights = @()
    foreach ($condGroup in ($Rows | Group-Object -Property 'レコードの条件')) {
        $entities = @($condGroup.Group | ForEach-Object {
            $orgName = $_.'組織名'
            @{
                entity      = @{ type = (Get-KintoneEntityType -Name $orgName); code = $(if ($orgName -eq "作成者") { $null } else { $orgName }) }
                viewable    = [bool](ToBool $_.'閲覧')
                editable    = [bool](ToBool $_.'編集')
                deletable   = [bool](ToBool $_.'削除')
                includeSubs = [bool](ToBool $_.'アクセス権の継承')
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

function Deploy-KintoneApps {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization,
        [Parameter(Mandatory)][string[]]$AppIds,
        [int]$TimeoutSeconds = 120
    )

    $uniqueIds = @($AppIds | Select-Object -Unique)
    if ($uniqueIds.Count -eq 0) { return }

    Write-Host "デプロイ開始: $($uniqueIds -join ', ')"

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
                throw "デプロイに失敗したアプリがあります: $($failed | ConvertTo-Json -Compress)"
            }
            Write-Host "デプロイ完了: $($uniqueIds -join ', ')"
            return
        }
        if ((Get-Date) -gt $deadline) {
            throw "デプロイがタイムアウトしました(${TimeoutSeconds}秒): $($resp.apps | ConvertTo-Json -Compress)"
        }
    }
}

# =========================================
# Excel入出力
# =========================================

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
            Write-Host "  (書き込み対象の行が無いためスキップ: $Path [$WorksheetName])" -ForegroundColor Yellow
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
    }
    Close-ExcelPackage $pkg
}
