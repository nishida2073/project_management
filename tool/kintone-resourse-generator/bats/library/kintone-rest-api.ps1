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
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            return Invoke-RestMethod -Uri $uri -Headers $headers -Method $Method -Body $bytes
        } else {
            return Invoke-RestMethod -Uri $uri -Headers $headers -Method $Method
        }
    } catch {
        throw
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
                throw "アプリ[$($app.name)]のACL取得に失敗: $($_.Exception.Message)"
            }
        }
    }

    if ($HasRecordAcl) {
        foreach ($app in $apps) {
            try {
                $recordAcl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/record/acl.json?app=$($app.appId)"
                $app.recordRights = @($recordAcl.rights)
            } catch {
                throw "アプリ[$($app.name)]のレコードACL取得に失敗: $($_.Exception.Message)"
            }
        }
    }

    $members = @()
    if ($HasMember) {
        $memberResp = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/space/members.json?id=$SpaceId"
        $members = @($memberResp.members)
    }

    return [PSCustomObject]@{
        spaceId        = $space.id
        spaceName      = $space.name
        isPrivate      = $space.isPrivate
        useMultiThread = $space.useMultiThread
        fixedMember    = $space.fixedMember
        createApp      = $space.permissions.createApp
        body           = $space.body
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
        throw "アプリID[$AppId]の設定取得に失敗: $($_.Exception.Message)"
    }

    $rights = @()
    try {
        $acl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/app/acl.json?app=$AppId"
        $rights = @($acl.rights)
    } catch {
        throw "アプリID[$AppId]のACL取得に失敗: $($_.Exception.Message)"
    }

    $recordRights = @()
    try {
        $recordAcl = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/record/acl.json?app=$AppId"
        $recordRights = @($recordAcl.rights)
    } catch {
        throw "アプリID[$AppId]のレコードACL取得に失敗: $($_.Exception.Message)"
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
        $CreateAppAdminOnly = $null,
        [string]$Body = $null
    )

    $spaceBody = @{ id = $SpaceId }
    if ($Name) { $spaceBody["name"] = $Name }
    if ($null -ne $IsPrivate) { $spaceBody["isPrivate"] = $IsPrivate }
    if ($null -ne $UseMultiThread) { $spaceBody["useMultiThread"] = $UseMultiThread }
    if ($null -ne $FixedMember) { $spaceBody["fixedMember"] = $FixedMember }
    if ($null -ne $CreateAppAdminOnly) {
        $spaceBody["permissions"] = @{ createApp = $(if ($CreateAppAdminOnly) { "ADMIN" } else { "EVERYONE" }) }
    }
    Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/space.json" -Body $spaceBody | Out-Null

    if ($Name) {
        $space = Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method GET -Path "/k/v1/space.json?id=$SpaceId"
        if ($space.defaultThread) {
            Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/space/thread.json" -Body @{ id = $space.defaultThread; name = $Name } | Out-Null
        }
    }

    if ($Body) {
        $bodyRequest = @{ id = $SpaceId; body = $Body }
        Invoke-KintoneRequest -BaseUrl $BaseUrl -Authorization $Authorization -Method PUT -Path "/k/v1/space/body.json" -Body $bodyRequest | Out-Null
    }
}

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
    return [PSCustomObject]@{
        TotalCount  = $body.members.Count
        KeptMembers = @($keptMembers | ForEach-Object {
            [PSCustomObject]@{
                Type        = Get-KintoneMemberTypeLabel $_.entity.type
                Code        = $_.entity.code
                IsAdmin     = $_.isAdmin
                IncludeSubs = $_.includeSubs
            }
        })
    }
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
            return
        }
        if ((Get-Date) -gt $deadline) {
            throw "更新がタイムアウトしました(${TimeoutSeconds}秒): $($resp.apps | ConvertTo-Json -Compress)"
        }
    }
}

function Test-KintoneConnection {
    param(
        [Parameter(Mandatory)][string]$Subdomain,
        [Parameter(Mandatory)][string]$LoginName,
        [Parameter(Mandatory)][string]$Password
    )
    $baseUrl = "https://$Subdomain.cybozu.com"
    $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${LoginName}:${Password}"))
    Invoke-KintoneRequest -BaseUrl $baseUrl -Authorization $authorization -Method GET -Path "/k/v1/apps.json?limit=1" | Out-Null
}

function Get-CurrentAppFieldData {
    param(
        [string]$TargetAppId,
        [string]$BaseUrl,
        [string]$Authorization
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $headers = @{
        "X-Cybozu-Authorization" = $Authorization
    }

    $Url = "$BaseUrl/k/v1/app/form/fields.json?app=$TargetAppId"
    try {
        $response = Invoke-RestMethod -Uri $Url -Headers $headers -Method GET
        Write-Message $response -VarName "response"
        return $response.properties
    } catch {
        throw
    }
}


function Get-NestedPropertyValue {
    param (
        [Parameter(Mandatory)]
        [object]$Object,
        [Parameter(Mandatory)]
        [string]$PropertyPath
    )
    $path = $PropertyPath -split '\.'
    $value = $Object
    foreach ($p in $path) {
        if ($null -eq $value) {
            return $null
        }
        $value = $value.$p
    }
    return $value
}


function Get-AllKintoneRecords {
    param(
        [string]$TargetAppId,
        [string]$BaseUrl,
        [string]$Authorization
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $headers = @{
        "X-Cybozu-Authorization" = $Authorization
    }

    $Url = "$BaseUrl/k/v1/records.json?app=$TargetAppId"

    try {
        $allRecords = New-Object System.Collections.Generic.List[object]
        $offset = 0
        $limit = 100
        while ($true) {
            $urlWithOffset = "$Url&limit=$limit&offset=$offset"
            Write-Message $urlWithOffset -VarName "urlWithOffset" -Type "Info"

            $response = Invoke-RestMethod -Uri $urlWithOffset -Headers $headers -Method GET
            if ($response.PSObject.Properties.Name -contains "records") {
                $records = $response.records
            } else {
                $records = ($response.PSObject.Properties |
                                Where-Object {
                                    $_.Value -is [System.Collections.IEnumerable] -and
                                    -not ($_.Value -is [string])
                                } |
                                Select-Object -First 1).Value
            }
            if (-not $records -or $records.Count -eq 0) {
                Write-Message "データなし" -VarName "message" -Type "Info"
                break
            }
            $allRecords.AddRange($records)

            if ($records.Count -lt $limit) {
                break
            }
            $offset += $limit
        }
        Write-Message $allRecords -VarName "allRecords" -Type "Info"
        return $allRecords
    } catch {
        throw
    }
}


function Get-DateKintoneRecords {
    param(
        [string]$TargetAppId,
        [string]$BaseUrl,
        [string]$Authorization,
        [string]$TargetDateCodeField,
        [string]$TargetDate
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $headers = @{
        "X-Cybozu-Authorization" = $Authorization
    }

    $Url = "$BaseUrl/k/v1/records.json?app=$TargetAppId&query=$TargetDateCodeField=`"$TargetDate`""

    try {
        $allRecords = New-Object System.Collections.Generic.List[object]
        $offset = 0
        $limit = 100
        while ($true) {
            $urlWithOffset = "$Url limit $limit offset $offset"
            Write-Message $urlWithOffset -VarName "urlWithOffset" -Type "Info"

            $response = Invoke-RestMethod -Uri $urlWithOffset -Headers $headers -Method GET
            if ($response.PSObject.Properties.Name -contains "records") {
                $records = $response.records
            } else {
                $records = ($response.PSObject.Properties |
                                Where-Object {
                                    $_.Value -is [System.Collections.IEnumerable] -and
                                    -not ($_.Value -is [string])
                                } |
                                Select-Object -First 1).Value
            }
            if (-not $records -or $records.Count -eq 0) {
                Write-Message "データなし" -VarName "message" -Type "Info"
                break
            }
            $allRecords.AddRange($records)

            if ($records.Count -lt $limit) {
                break
            }
            $offset += $limit
        }
        Write-Message $allRecords -VarName "allRecords" -Type "Info"
        return $allRecords
    } catch {
        throw
    }
}


function Add-KintoneFile {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    Add-Type -AssemblyName System.Net.Http

    $Url = "$BaseUrl/k/v1/file.json"
    $httpClient = [System.Net.Http.HttpClient]::new()
    try {
        $httpClient.DefaultRequestHeaders.Add("X-Cybozu-Authorization", $Authorization)

        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $fileContent = [System.Net.Http.ByteArrayContent]::new($fileBytes)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")

        $content = [System.Net.Http.MultipartFormDataContent]::new()
        $content.Add($fileContent, "file", [System.IO.Path]::GetFileName($FilePath))

        $response = $httpClient.PostAsync($Url, $content).GetAwaiter().GetResult()
        $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "ファイルアップロード 失敗: $($response.StatusCode) $responseBody"
        }
        $result = $responseBody | ConvertFrom-Json
        Write-Message $result -VarName "response"
        return $result.fileKey
    } catch {
        throw
    } finally {
        $httpClient.Dispose()
    }
}


function Add-KintoneThreadComment {
    param(
        [Parameter(Mandatory)][string]$SpaceId,
        [Parameter(Mandatory)][string]$ThreadId,
        [string]$Text,
        [string[]]$FilePaths = @(),
        [array]$Mentions = @(),
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Authorization
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    if ([string]::IsNullOrWhiteSpace($Text) -and $FilePaths.Count -eq 0) {
        throw "TextとFilePathsのどちらか一方は指定してください。"
    }

    $files = @($FilePaths | ForEach-Object {
        @{ fileKey = (Add-KintoneFile -FilePath $_ -BaseUrl $BaseUrl -Authorization $Authorization) }
    })

    $comment = @{}
    if ($Text) { $comment.text = $Text }
    if ($files.Count -gt 0) { $comment.files = $files }
    if ($Mentions.Count -gt 0) { $comment.mentions = $Mentions }

    $body = @{
        space   = $SpaceId
        thread  = $ThreadId
        comment = $comment
    }

    $headers = @{
        "X-Cybozu-Authorization" = $Authorization
        "Content-Type"           = "application/json; charset=utf-8"
    }
    $Url = "$BaseUrl/k/v1/space/thread/comment.json"

    try {
        $bodyJson = $body | ConvertTo-Json -Depth 10
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
        $response = Invoke-RestMethod -Uri $Url -Headers $headers -Method POST -Body $bodyBytes
        Write-Message $response -VarName "response"
        return $response
    } catch {
        $detail = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        throw $detail
    }
}

function Test-KintoneConnectionWithAppId {
    param(
        [Parameter(Mandatory)][string]$Subdomain,
        [Parameter(Mandatory)][string]$LoginName,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string[]]$AppIds
    )
    $baseUrl = "https://$Subdomain.cybozu.com"
    $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${LoginName}:${Password}"))
    $resultLines = @()
    $hasFailure = $false
    foreach ($targetAppId in $AppIds) {
        try {
            $fieldData = Get-CurrentAppFieldData -TargetAppId $targetAppId -BaseUrl $baseUrl -Authorization $authorization
            $fieldCodes = @($fieldData.PSObject.Properties.Name)
            $resultLines += "[成功] $targetAppId（フィールド数: $($fieldCodes.Count)）"
            $resultLines += "  $($fieldCodes -join ', ')"
        } catch {
            $hasFailure = $true
            $resultLines += "[失敗] $targetAppId： $($_.Exception.Message)"
        }
    }
    $resultText = $resultLines -join "`r`n"
    if ($hasFailure) { throw $resultText }
    return $resultText
}
