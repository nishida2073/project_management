param([int]$MinSpaceId, [int]$MaxSpaceId)

if ($MinSpaceId -lt 1 -or $MaxSpaceId -lt 1 -or $MinSpaceId -gt $MaxSpaceId) {
    Write-Host "使用法: remove-space.ps1 <MinSpaceId> <MaxSpaceId>"
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$batFile = Join-Path $scriptDir "K01.bat"
$logFile = Join-Path $scriptDir "remove-space.log"

$lines = @(Get-Content $batFile)
$config = @{}
foreach ($line in $lines) {
    if ($line -match 'set "([^=]+)=([^"]*)"') {
        $config[$matches[1]] = $matches[2]
    }
}

$subDomain = $config["KINTONE_SUB_DOMAIN"]
$login = $config["KINTONE_LOGIN"]
$password = $config["KINTONE_PASSWORD"]

if ([string]::IsNullOrEmpty($subDomain) -or [string]::IsNullOrEmpty($login) -or [string]::IsNullOrEmpty($password)) {
    Write-Host "K01.bat から設定値を読み込めませんでした"
    exit 1
}

$auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($login):$($password)"))
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content $logFile "[$timestamp] スペースID $MinSpaceId ～ $MaxSpaceId を削除開始"

$successCount = 0
$failureCount = 0

for ($spaceId = $MinSpaceId; $spaceId -le $MaxSpaceId; $spaceId++) {
    $url = "https://$subDomain.cybozu.com/k/v1/space.json"
    $body = @{ id = $spaceId } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $url -Method Delete -Headers @{
            "X-Cybozu-Authorization" = $auth
            "Content-Type" = "application/json"
        } -Body $body
        Write-Host "スペース ID $spaceId を削除しました"
        Add-Content $logFile "[$timestamp] 成功: スペース ID $spaceId を削除"
        $successCount++
    } catch {
        Write-Host "スペース ID ${spaceId}: $($_.Exception.Message)"
        Add-Content $logFile "[$timestamp] 失敗: スペース ID $spaceId - $($_.Exception.Message)"
        $failureCount++
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content $logFile "[$timestamp] 完了 - 成功: $successCount, 失敗: $failureCount"
Write-Host "処理完了 - 成功: $successCount, 失敗: $failureCount"
Write-Host "ログ: $logFile"