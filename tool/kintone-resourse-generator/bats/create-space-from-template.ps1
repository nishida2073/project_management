# =========================================
# スペーステンプレートから新しいスペースを作成する
# =========================================

param(
    [string]$TemplateId,
    [string]$SpaceName
)

$libraryDir = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

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
        Write-MessageError "スペース作成に失敗しました: $($_.Exception.Message)"
        $script:exitCode = 1
        return
    }

    $script:newSpaceId = $newSpaceId
    Write-Message "" -Type "Info" -NoHeader
    Write-ApplyStepResult -ActionLabel "スペースを作成しました" -DetailLines @(
        "　スペースID: $newSpaceId"
        "　スペース名：$SpaceName"
    )
    Write-Message "　SPACE_ID=$newSpaceId" -Type "Info" -NoHeader -Hidden
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-MessageComplete "ログを出力しました: $logFilePath"
exit $script:exitCode
