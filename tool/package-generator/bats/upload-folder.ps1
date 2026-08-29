# =========================================
# ローカルフォルダ→SharePointアップロードツール（Azure CLI + Microsoft Graph版）
# =========================================
# download-folder.ps1と同じ仕組み（Azure CLIで取得したトークンでMicrosoft Graph APIを直接呼ぶ）の逆方向版。

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "library\common.ps1")
$startTime = Get-Date

$siteUrl = $env:UPLOAD_SITE_URL
$sitePath = $env:UPLOAD_SITE_PATH
$tenantId = $env:UPLOAD_SITE_TENANT_ID
$localPath = $env:UPLOAD_LOCAL_PATH

if (!$siteUrl -or !$sitePath -or !$tenantId -or !$localPath) {
    Write-Message "UPLOAD_SITE_URL と UPLOAD_SITE_PATH と UPLOAD_SITE_TENANT_ID と UPLOAD_LOCAL_PATH を set-env.bat で設定してください" -ForegroundColor Red
    exit 1
}

if (!(Test-Path -LiteralPath $localPath)) {
    Write-Message "アップロード元が存在しません：$localPath" -ForegroundColor Red
    exit 1
}

$logPath = $env:COMMON_LOG_PATH
New-Item -ItemType Directory -Path $logPath -Force | Out-Null

$uploadLog = @()

$az = Get-AzureCliPath
$token = Get-GraphToken -Az $az -TenantId $tenantId
$headers = @{ Authorization = "Bearer $token" }

$siteId = Resolve-GraphSiteId -Headers $headers -SiteUrl $siteUrl

$folderParts = $sitePath -split '/'
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
        Write-Message "操作中：$currentName"
        try {
            Send-FileToSharePoint -LocalFile $currentFile -SiteRelativePath $fileSitePath
            $script:uploadLog += "$currentFile -> $sitePath/$SubPath"
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

$topLevelItems = Get-ChildItem -LiteralPath $localPath

if ($env:UPLOAD_ITEMS_INCLUDE) {
    $includePatterns = $env:UPLOAD_ITEMS_INCLUDE.Split(",") | ForEach-Object { $_.Trim() }
    $topLevelItems = $topLevelItems | Where-Object { Test-NameMatchesPatterns -Name $_.Name -Patterns $includePatterns }
}

if ($env:UPLOAD_ITEMS_EXCLUDE) {
    $excludePatterns = $env:UPLOAD_ITEMS_EXCLUDE.Split(",") | ForEach-Object { $_.Trim() }
    $topLevelItems = $topLevelItems | Where-Object { !(Test-NameMatchesPatterns -Name $_.Name -Patterns $excludePatterns) }
}

$topLevelItems | ForEach-Object {
    Send-Item -Item $_ -SubPath $_.Name
}

$endTime = Get-Date
$logFilePath = Write-RunLogFile -LogPath $logPath -LogFileName "$($env:UPLOAD_LOG_PREFIX)$(Get-ClientLogSegment)$(Split-Path $relativeFolder -Leaf).log" `
    -StartTime $startTime -EndTime $endTime `
    -ResultSectionTitle "アップロード結果" -ResultLines $uploadLog `
    -ItemListRootPath $localPath -ItemListPaths @($topLevelItems | ForEach-Object { $_.FullName })
Show-LogFileContent -Path $logFilePath