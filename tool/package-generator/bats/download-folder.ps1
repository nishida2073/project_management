# =========================================
# Teams/SharePointファイル取得ツール（Azure CLI + Microsoft Graph版）
# =========================================

param(
    [string]$SiteUrl,
    [string]$SitePath,
    [string]$TenantId,
    [string]$LocalPath,
    [string]$LogPath,
    [string]$LogPrefix,
    [string]$ClientName = ""
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $scriptDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}
$startTime = Get-Date

if (!$SiteUrl -or !$SitePath -or !$TenantId) {
    Write-MessageError "SiteUrl と SitePath と TenantId を指定してください"
    exit 1
}

New-Item -ItemType Directory -Path $LogPath -Force | Out-Null

$downloadLog = @()

$az = Get-AzureCliPath
$token = Get-GraphToken -Az $az -TenantId $TenantId
$headers = @{ Authorization = "Bearer $token" }

$siteId = Resolve-GraphSiteId -Headers $headers -SiteUrl $SiteUrl

$folderParts = $SitePath -split '/'
$relativeFolder = ($folderParts | Select-Object -Skip 1) -join '/'
$encodedRelativeFolder = Get-EncodedSitePath $relativeFolder

$startUri = if ($relativeFolder) {
    "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root:/${encodedRelativeFolder}"
} else {
    "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root"
}
$startItem = Invoke-GraphGet -Headers $headers -Uri $startUri

function Get-GraphChildrenRecursive {
    param(
        [string]$ItemId,
        [string]$LocalFolder,
        [string]$RelativePath
    )

    New-Item -ItemType Directory -Path $LocalFolder -Force | Out-Null

    $uri = "https://graph.microsoft.com/v1.0/sites/$siteId/drive/items/$ItemId/children"
    while ($uri) {
        $page = Invoke-GraphGet -Headers $headers -Uri $uri
        foreach ($item in $page.value) {
            if ($item.file) {
                $dest = Join-Path $LocalFolder $item.Name
                Write-Message "操作中：$($item.Name)" -Type "Info" -NoHeader

                $maxRetry = 8
                $succeeded = $false
                $lastErrorDetail = $null
                for ($retry = 1; $retry -le $maxRetry; $retry++) {
                    try {
                        Invoke-WebRequest -Uri $item.'@microsoft.graph.downloadUrl' -OutFile $dest -UseBasicParsing
                        $succeeded = $true
                        break
                    } catch {
                        $lastErrorDetail = $_.Exception.Message
                        if ($retry -lt $maxRetry) {
                            Start-Sleep -Milliseconds (1000 * $retry)
                        }
                    }
                }

                if ($succeeded) {
                    $script:downloadLog += "$RelativePath/$($item.Name) -> $dest"
                } else {
                    $script:downloadLog += "$RelativePath/$($item.Name) -> エラー: $lastErrorDetail"
                }
            } elseif ($item.folder) {
                Get-GraphChildrenRecursive -ItemId $item.id -LocalFolder (Join-Path $LocalFolder $item.Name) -RelativePath "$RelativePath/$($item.Name)"
            }
        }
        $uri = $page.'@odata.nextLink'
    }
}

$logNamePrefix = "$($LogPrefix)$(if ($ClientName) { "${ClientName}_" } else { "${defaultClientLabel}_" })$(Split-Path $SitePath -Leaf)"
$logFilePath = New-WorkerLogPath -LogRoot $LogPath -Prefix $logNamePrefix -Timestamp $startTime

& {
    Get-GraphChildrenRecursive -ItemId $startItem.id -LocalFolder $LocalPath -RelativePath $SitePath
    Write-Message (Get-RunLogMessage -ResultSectionTitle "ダウンロード結果" -ResultLines $downloadLog -TreeRootPath $LocalPath) -Type "Info" -NoHeader
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-MessageComplete "ログを出力しました: $logFilePath"
