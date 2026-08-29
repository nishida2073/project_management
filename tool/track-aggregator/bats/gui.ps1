# =========================================
# GUI（trackデータ集計ツール）
# =========================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path
    $rootPath = Split-Path $scriptDir -Parent
} else {
    $rootPath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
# build-gui.ps1でps2exeビルドした実行ファイルはプロジェクトルートに置かれるため、batsフォルダを別途辿る
$basePath = Join-Path $rootPath "bats"

$libraryDir = Join-Path $basePath "library"
Get-ChildItem -Path $libraryDir -Filter *.psm1 -Recurse | ForEach-Object {
    Import-Module $_.FullName -ErrorAction Stop -DisableNameChecking
}

# 子プロセス（Invoke-BatStep経由で起動するbat/ps1）のWrite-Messageに、
# GUIログ向けの色タグ付き出力へ切り替えさせる合図
$env:GUI_LOG_MODE = "1"

$script:commonEnvVars = Get-BatEnvVars -BatPath (Join-Path $basePath "common-env.bat")

# GUIのタブ（カテゴリ）とその中に並べるボタンの定義。並べ方や見た目はNew-CategoryTabControl側の責務
$categoryDefs = @(
    [PSCustomObject]@{
        Label = "実施データ取得"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "データ取得"; BatchPath = (Join-Path $basePath "download-results.bat"); TargetDirPath = $script:commonEnvVars["MasterDataRootDir"] }
            [PSCustomObject]@{ Label = "取得状況確認"; BatchPath = (Join-Path $basePath "check-download-status.bat"); TargetDirPath = $script:commonEnvVars["ResultRootDir"] }
        )
    }
    [PSCustomObject]@{
        Label = "実施状況確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート集計"; BatchPath = (Join-Path $basePath "collect-combine-result.bat"); TargetDirPath = $script:commonEnvVars["OutputCombineCollectDir"] }
        )
    }
    [PSCustomObject]@{
        Label = "実施結果確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト集計"; BatchPath = (Join-Path $basePath "collect-test-result.bat"); TargetDirPath = $script:commonEnvVars["OutputTestCollectDir"] }
            [PSCustomObject]@{ Label = "アンケート集計"; BatchPath = (Join-Path $basePath "collect-survey-result.bat"); TargetDirPath = $script:commonEnvVars["OutputSurveyCollectDir"] }
            [PSCustomObject]@{
                Label = "経年比較集計"
                BatchPath = (Join-Path $basePath "collect-year-comparison-result.bat")
                TargetDirPath = $script:commonEnvVars["OutputYearComparisonCollectDir"]
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetCompanyNames"; Label = "対象の会社名"; Default = $script:commonEnvVars["TargetCompanyNames"]; LabelWidth = 85; InputWidth = 260 }
                    [PSCustomObject]@{ Name = "ComparePeriod"; Label = "比較年"; Default = $script:commonEnvVars["ComparePeriod"]; LabelWidth = 50; InputWidth = 40 }
                    [PSCustomObject]@{
                        Name = "YearOrder"; Label = "表示順"; Default = $script:commonEnvVars["YearOrder"]; LabelWidth = 55; InputWidth = 70
                        Options = @(
                            [PSCustomObject]@{ Text = "昇順"; Value = "0" }
                            [PSCustomObject]@{ Text = "降順"; Value = "1" }
                        )
                    }
                )
            }
        )
    }
)

$form = New-Object System.Windows.Forms.Form
$form.Text = "trackデータ集計ツール"
$form.Size = New-Object System.Drawing.Size(780, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(600, 400)

$script:currentProc = $null
$form.Add_FormClosing({
    if ($script:currentProc -and !$script:currentProc.HasExited) {
        & taskkill.exe /T /F /PID $script:currentProc.Id 2>&1 | Out-Null
    }
})

# =========================================
# 実行タブ（カテゴリごとに分割）
# =========================================

$tabResult = New-CategoryTabControl -CategoryDefs $categoryDefs -OnRunClick { param($bd) Invoke-BatButton -ButtonDef $bd }
$tabControl = $tabResult.TabControl
$script:runButtons = $tabResult.RunButtons
$script:stepStatusLabels = $tabResult.StepStatusLabels
$script:inputControls = $tabResult.InputControls

function Set-StepStatus {
    param([string]$Label, [string]$Text)
    $color = switch ($Text) {
        "実行中..." { [System.Drawing.Color]::Black }
        "成功"      { [System.Drawing.Color]::DarkGreen }
        "失敗"      { [System.Drawing.Color]::DarkRed }
        default     { [System.Drawing.Color]::Gray }
    }
    Set-StatusLabelText -Label $script:stepStatusLabels[$Label] -Text $Text -ForeColor $color
}

# =========================================
# ログ（タブ切替に関わらず常に表示）
# =========================================

$logSpacer = New-Object System.Windows.Forms.Panel
$logSpacer.Height = 10
$logSpacer.Dock = [System.Windows.Forms.DockStyle]::Top

$txtLog = New-LogTextBox

# 視覚的な上→下の並び: tabControl → logSpacer → txtLog（Dock=Fillで残り全域を埋める）
Add-StackedDockedControls -Container $form -ControlsTopToBottom @($tabControl, $logSpacer, $txtLog)

function Write-Log {
    param([string]$Text)
    Write-ColoredLine -TextBox $txtLog -Text $Text
}

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    Set-ButtonsEnabled -Buttons $script:runButtons.Values -Enabled $Enabled
}

function Invoke-BatButton {
    param($ButtonDef)

    Set-RunButtonsEnabled $false
    Set-StepStatus -Label $ButtonDef.Label -Text "実行中..."

    Write-Log ""
    Write-Log "--------------- $($ButtonDef.Label) 開始 ---------------"

    $batArgs = @()
    $inputMap = $script:inputControls[$ButtonDef.Label]
    if ($inputMap) {
        foreach ($inputName in $inputMap.Keys) {
            $batArgs += "$($inputName):$(Get-InputValue -Control $inputMap[$inputName])"
        }
    }

    $exitCode = Invoke-BatStep -BatPath $ButtonDef.BatchPath -WorkingDirectory $basePath -BatArgs $batArgs `
        -OnOutputLine { param($line) Write-Log $line } `
        -CurrentProcessRef ([ref]$script:currentProc)

    Show-FormInForeground -Form $form

    if ($exitCode -ne 0) {
        Write-Log "--------------- $($ButtonDef.Label) 失敗（終了コード: $exitCode） ---------------"
        Set-StepStatus -Label $ButtonDef.Label -Text "失敗"
    } else {
        Write-Log "--------------- $($ButtonDef.Label) 完了 ---------------"
        Set-StepStatus -Label $ButtonDef.Label -Text "成功"
    }

    Set-RunButtonsEnabled $true
}

[System.Windows.Forms.Application]::Run($form)
