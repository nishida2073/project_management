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


function Get-CurrentAppData {
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
