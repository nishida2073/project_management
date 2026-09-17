# =========================================
# ローカルフォルダ→SharePointアップロードツール（Azure CLI + Microsoft Graph版）
# =========================================
# download-folder.ps1と同じ仕組み（Azure CLIで取得したトークンでMicrosoft Graph APIを直接呼ぶ）の逆方向版。

param(
    [string]$SiteUrl,
    [string]$SitePath,
    [string]$TenantId,
    [string]$LocalPath,
    [string]$LogPath,
    [string]$LogPrefix,
    [string]$ItemsInclude,
    [string]$ItemsExclude,
    [string]$ClientName = ""
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $scriptDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}
$startTime = Get-Date

if (!$SiteUrl -or !$SitePath -or !$TenantId -or !$LocalPath) {
    Write-MessageError "SiteUrl と SitePath と TenantId と LocalPath を指定してください"
    exit 1
}

if (!(Test-Path -LiteralPath $LocalPath)) {
    Write-MessageError "アップロード元が存在しません：$LocalPath"
    exit 1
}

New-Item -ItemType Directory -Path $LogPath -Force | Out-Null

$uploadLog = @()

$az = Get-AzureCliPath
$token = Get-GraphToken -Az $az -TenantId $TenantId
$headers = @{ Authorization = "Bearer $token" }

$siteId = Resolve-GraphSiteId -Headers $headers -SiteUrl $SiteUrl

$folderParts = $SitePath -split '/'
$relativeFolder = ($folderParts | Select-Object -Skip 1) -join '/'

function Send-EmptyFileToSharePoint {
    param(
        [string]$SiteRelativePath
    )

    $encodedPath = Get-EncodedSitePath $SiteRelativePath
    $contentUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root:/${encodedPath}:/content"

    $maxRetry = 8
    for ($retry = 1; $retry -le $maxRetry; $retry++) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($contentUri)
            $req.Method = "PUT"
            $req.KeepAlive = $false
            $req.Headers.Add("Authorization", $headers.Authorization)
            $req.ContentLength = 0
            $webResp = $req.GetResponse()
            $webResp.Close()
            break
        } catch {
            if ($retry -eq $maxRetry) { throw }
            Start-Sleep -Milliseconds (1000 * $retry)
        }
    }
}

function Send-FileToSharePoint {
    param(
        [string]$LocalFile,
        [string]$SiteRelativePath
    )

    $fileSize = (Get-Item -LiteralPath $LocalFile).Length

    if ($fileSize -eq 0) {
        Send-EmptyFileToSharePoint -SiteRelativePath $SiteRelativePath
        return
    }

    $encodedPath = Get-EncodedSitePath $SiteRelativePath
    $sessionUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root:/${encodedPath}:/createUploadSession"
    $sessionBody = '{"item":{"@microsoft.graph.conflictBehavior":"replace"}}'
    $session = Invoke-GraphPost -Headers $headers -Uri $sessionUri -Body $sessionBody
    $uploadUrl = $session.uploadUrl

    $fileStream = [System.IO.File]::OpenRead($LocalFile)
    try {
        $chunkSize = 10485760
        $buffer = New-Object byte[] $chunkSize
        $offset = 0
        $totalSize = [Math]::Max($fileSize, 0)

        do {
            $readSize = [Math]::Min($chunkSize, $fileSize - $offset)
            $fileStream.Position = $offset
            $bytesRead = if ($fileSize -eq 0) { 0 } else { $fileStream.Read($buffer, 0, $readSize) }
            $rangeEnd = [Math]::Max($offset + $bytesRead - 1, 0)
            $rangeHeader = "bytes $offset-$rangeEnd/$totalSize"

            $maxRetry = 8
            for ($retry = 1; $retry -le $maxRetry; $retry++) {
                try {
                    $req = [System.Net.HttpWebRequest]::Create($uploadUrl)
                    $req.Method = "PUT"
                    $req.KeepAlive = $false
                    $req.Headers.Add("Content-Range", $rangeHeader)
                    $req.ContentLength = $bytesRead
                    if ($bytesRead -gt 0) {
                        $reqStream = $req.GetRequestStream()
                        $reqStream.Write($buffer, 0, $bytesRead)
                        $reqStream.Close()
                    }
                    $webResp = $req.GetResponse()
                    $webResp.Close()
                    break
                } catch {
                    if ($retry -eq $maxRetry) { throw }
                    Start-Sleep -Milliseconds (1000 * $retry)
                }
            }

            $offset += $bytesRead
        } while ($offset -lt $fileSize)
    } finally {
        $fileStream.Close()
    }
}

function Send-Item {
    param(
        [System.IO.FileSystemInfo]$Item,
        [string]$SubPath
    )

    if ($Item.PSIsContainer) {
        Send-FolderRecursive -LocalFolder $Item.FullName -SubPath $SubPath
    } else {
        $currentFile = $Item.FullName
        $currentName = $Item.Name
        $fileSitePath = if ($relativeFolder) { "$relativeFolder/$SubPath" } else { $SubPath }
        Write-Message "操作中：$currentName" -Type "Info" -NoHeader
        try {
            Send-FileToSharePoint -LocalFile $currentFile -SiteRelativePath $fileSitePath
            $script:uploadLog += "$currentFile -> $SitePath/$SubPath"
        } catch {
            $script:uploadLog += "$currentFile -> エラー: $($_.Exception.Message)"
        }
    }
}

function Send-FolderRecursive {
    param(
        [string]$LocalFolder,
        [string]$SubPath
    )

    Get-ChildItem -LiteralPath $LocalFolder | ForEach-Object {
        $childSubPath = if ($SubPath) { "$SubPath/$($_.Name)" } else { $_.Name }
        Send-Item -Item $_ -SubPath $childSubPath
    }
}

$topLevelItems = Get-ChildItem -LiteralPath $LocalPath

if ($ItemsInclude) {
    $includePatterns = $ItemsInclude.Split(",") | ForEach-Object { $_.Trim() }
    $topLevelItems = $topLevelItems | Where-Object { Test-NameMatchesPatterns -Name $_.Name -Patterns $includePatterns }
}

if ($ItemsExclude) {
    $excludePatterns = $ItemsExclude.Split(",") | ForEach-Object { $_.Trim() }
    $topLevelItems = $topLevelItems | Where-Object { !(Test-NameMatchesPatterns -Name $_.Name -Patterns $excludePatterns) }
}

$logNamePrefix = "$($LogPrefix)$(if ($ClientName) { "${ClientName}_" } else { "${defaultClientLabel}_" })$(Split-Path $relativeFolder -Leaf)"
$logFilePath = New-WorkerLogPath -LogRoot $LogPath -Prefix $logNamePrefix -Timestamp $startTime

& {
    $topLevelItems | ForEach-Object {
        Send-Item -Item $_ -SubPath $_.Name
    }
    $message = Get-RunLogMessage -ResultSectionTitle "アップロード結果" -ResultLines $uploadLog `
        -ItemListRootPath $LocalPath -ItemListPaths @($topLevelItems | ForEach-Object { $_.FullName })
    Write-Message $message -Type "Info" -NoHeader
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-MessageComplete "ログを出力しました: $logFilePath"
