# =========================================
# スペーステンプレートから新しいスペースを作成する
# =========================================
# kintoneの「スペーステンプレート」機能を使い、指定したテンプレートIDから新しいスペースを作成する。
# 元スペースを「テンプレートとして保存」する操作自体はAPIには無いため、kintoneの管理画面で
# 事前に済ませておく必要がある（テンプレートIDはその管理画面のURLから確認できる）。

param(
    [string]$TemplateId,
    [string]$SpaceName
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "library\common.ps1")

$baseUrl = $env:KINTONE_BASE_URL
$logRoot = $env:COMMON_LOG_PATH

if (-not $baseUrl -or -not $logRoot) {
    Write-Message "KINTONE_BASE_URL / COMMON_LOG_PATH を設定してください（clients\set-kintone.bat・set-env.bat）" -Type "Info" -NoHeader
    exit 1
}
if (-not $TemplateId) {
    $TemplateId = Read-Host "スペーステンプレートID"
}
if (-not $SpaceName) {
    $SpaceName = Read-Host "作成するスペースの名前"
}

$logFilePath = New-WorkerLogPath -LogRoot $logRoot -Prefix "createspace_$SpaceName"

$script:exitCode = 0
$script:newSpaceId = $null

& {
    $authorization = Get-KintoneAuthorizationHeader -BaseUrl $baseUrl

    $newSpaceId = $null
    try {
        $newSpaceId = New-KintoneSpaceFromTemplate -BaseUrl $baseUrl -Authorization $authorization -TemplateId $TemplateId -Name $SpaceName -AdminLogin $script:kintoneLogin
    } catch {
        Write-Message "スペース作成に失敗しました: $($_.Exception.Message)" -ForegroundColor Red -Type "Info" -NoHeader
        $script:exitCode = 1
        return
    }

    $script:newSpaceId = $newSpaceId
    Write-Message "" -Type "Info" -NoHeader
    Write-Message "スペースを作成しました: スペース名=$SpaceName" -ForegroundColor Green -Type "Info" -NoHeader
    Write-Message "作成されたスペースID: $newSpaceId" -ForegroundColor Green -Type "Info" -NoHeader
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Message "" -Type "Info" -NoHeader
Write-Message "ログを出力しました: $logFilePath" -ForegroundColor Green -Type "Info" -NoHeader
exit $script:exitCode
