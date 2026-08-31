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
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

# 子プロセス（Invoke-BatStep経由で起動するbat/ps1）のWrite-Messageに、
# GUIログ向けの色タグ付き出力へ切り替えさせる合図
$env:GUI_LOG_MODE = "1"

# ログファイルはbats\*.bat経由で起動される各.ps1本体が自分で書き出す
# （New-WorkerLogPath/Tee-Objectを使う方式。bats\library\common.ps1参照）ため、
# GUI側では何もしない（以前はここでGUI独自にログファイルを書き出していたが、
# .ps1側に統一したため不要になった）
$script:commonEnvVars = Get-BatEnvVars -BatPath (Join-Path $basePath "common-env.bat")

# GUIのタブ（カテゴリ）とその中に並べるボタンの定義。並べ方や見た目はNew-CategoryTabControl側の責務
$categoryDefs = @(
    [PSCustomObject]@{
        Label = "実施データ取得"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施データ取得-テスト・アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "download-results.bat"); TargetDirPath = $script:commonEnvVars["MasterDataRootDir"] }
            [PSCustomObject]@{ Label = "取得状況確認"; BatchLabel = "実施データ取得-取得状況確認"; IncludeInBatch = $false; BatchPath = (Join-Path $basePath "check-download-status.bat"); TargetDirPath = $script:commonEnvVars["ResultRootDir"] }
        )
    }
    [PSCustomObject]@{
        Label = "実施状況確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施状況確認-テスト・アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-combine-result.bat"); TargetDirPath = $script:commonEnvVars["OutputCombineCollectDir"] }
        )
    }
    [PSCustomObject]@{
        Label = "実施結果確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト"; BatchLabel = "実施結果確認-テスト"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-test-result.bat"); TargetDirPath = $script:commonEnvVars["OutputTestCollectDir"] }
            [PSCustomObject]@{ Label = "アンケート"; BatchLabel = "実施結果確認-アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-survey-result.bat"); TargetDirPath = $script:commonEnvVars["OutputSurveyCollectDir"] }
            [PSCustomObject]@{
                Label = "経年比較"
                BatchLabel = "実施結果確認-経年比較"
                IncludeInBatch = $true
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
# 一括実行タブ（package-generatorの実行タブUIを参考にしたレイアウト：
# チェックボックスで対象ステップを選び、1つの実行ボタンで一括実行する）
#
# 先頭タブにするため、TabControlをここで作ってこのタブを最初にAddし、
# 後段の「実行タブ（カテゴリごと）」ではこのTabControlに追記してもらう形にする。
# ps2exeでビルドした実行ファイルではTabPageCollection.Insert()がNotSupportedExceptionになるため、
# 後から並び替えるのではなく、最初から最終的な順序でAddしていく必要がある
# =========================================

$tabControl = New-Object System.Windows.Forms.TabControl

# IncludeInBatchを$falseにしたButtonDefだけ、一括実行タブの対象から外せる（実行タブ側には影響しない）
$allButtonDefs = @()
foreach ($cd in $categoryDefs) {
    foreach ($bd in $cd.ButtonDefs) {
        if ($bd.IncludeInBatch -ne $false) { $allButtonDefs += $bd }
    }
}

# 一括実行タブでの表示名。BatchLabelがあればそれを、無ければ実行タブ側のLabelを使う。
# チェックボックスの表示名とログの文言が食い違わないよう、一括実行タブ関連のログは
# 必ずこの関数を通す（$ButtonDef.Labelを直接使わない）
function Get-BatchDisplayLabel {
    param($ButtonDef)
    if ($ButtonDef.BatchLabel) { $ButtonDef.BatchLabel } else { $ButtonDef.Label }
}

$tabBatchAll = New-Object System.Windows.Forms.TabPage
$tabBatchAll.Text = "一括実行"
$tabControl.Controls.Add($tabBatchAll)

$batchPanel = New-Object System.Windows.Forms.Panel
$batchPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$tabBatchAll.Controls.Add($batchPanel)

# ステップごとのチェックボックス＋開くリンク（チェックを外したステップは「一括実行」の対象外になる）。
# このツールはボタンごとに入力欄の内容が異なり（経年比較集計だけが専用の入力欄を持つ）、
# 全ボタン共通の入力欄は無いため、一括実行タブには入力欄を置かない。
# チェックボックスはLabelではなく$allButtonDefsと同じ並び順のインデックスで対応付ける
# （Labelはカテゴリをまたいで重複し得るため、Labelをキーにするとハッシュテーブルで
# 上書きが起きてチェック状態を取り違える）
$script:batchStepCheckboxes = @()
$batchTopControls = @()
$y = 20
foreach ($bd in $allButtonDefs) {
    # Inputsを持つステップ（経年比較集計）は一括実行タブで値を確認・変更できず、
    # common-env.bat由来の既定値のまま実行されてしまうため、既定はチェックを外しておく。
    # BatchLabelの長さはボタンごとに異なるため、AutoSizeで実測幅に合わせると「開く」の位置が
    # ずれて見切れたり画面外に出たりする。チェックボックスを固定幅＋省略表示にして「開く」の位置を固定する
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = Get-BatchDisplayLabel -ButtonDef $bd
    $chk.Checked = if ($bd.Inputs) { $false } else { $true }
    $chk.AutoSize = $false
    $chk.AutoEllipsis = $true
    $chk.Size = New-Object System.Drawing.Size(500, 22)
    $chk.Location = New-Object System.Drawing.Point(20, $y)
    $script:batchStepCheckboxes += $chk
    $batchTopControls += $chk

    if ($bd.TargetDirPath) {
        $lnkOpen = New-Object System.Windows.Forms.LinkLabel
        $lnkOpen.Text = "開く"
        $lnkOpen.AutoSize = $false
        $lnkOpen.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $lnkOpen.Size = New-Object System.Drawing.Size(40, $chk.Height)
        $lnkOpen.Location = New-Object System.Drawing.Point(530, $y)
        $lnkOpen.Tag = $bd
        $lnkOpen.Add_LinkClicked({ Open-FolderOrWarn -Path $this.Tag.TargetDirPath })
        $batchTopControls += $lnkOpen
    }

    $y += 26
}

$btnRunAll = New-Object System.Windows.Forms.Button
$btnRunAll.Text = "一括実行"
$btnRunAll.Location = New-Object System.Drawing.Point(20, ($y + 10))
$btnRunAll.Size = New-Object System.Drawing.Size(120, 28)
$batchTopControls += $btnRunAll
$script:batchRunButtons = @($btnRunAll)

$lblBatchStatus = New-Object System.Windows.Forms.Label
$lblBatchStatus.Text = ""
$lblBatchStatus.AutoSize = $true
$lblBatchStatus.Location = New-Object System.Drawing.Point(154, ($y + 16))
$lblBatchStatus.Font = New-Object System.Drawing.Font($lblBatchStatus.Font, [System.Drawing.FontStyle]::Bold)
$batchTopControls += $lblBatchStatus

$batchPanel.Controls.AddRange($batchTopControls)
$batchPanel.Height = $y + 10 + 28 + 16

$btnRunAll.Add_Click({ Invoke-BatchRunAll })

# 一括実行タブでの1ステップ分の実行本体（「一括実行」から順番に呼ばれる）
function Invoke-BatchStep {
    param($ButtonDef)

    Write-Log ""
    Write-Log "--------------- $(Get-BatchDisplayLabel -ButtonDef $ButtonDef) 開始 ---------------"

    # 一括実行タブには個別タブのような専用入力欄が無いため、Inputsが定義されたステップ
    # （経年比較集計）はcommon-env.bat由来の既定値（Default）をそのまま使う
    $batArgs = @()
    foreach ($inputDef in $ButtonDef.Inputs) {
        $batArgs += "$($inputDef.Name):$($inputDef.Default)"
    }

    $exitCode = Invoke-BatStep -BatPath $ButtonDef.BatchPath -WorkingDirectory $basePath -BatArgs $batArgs `
        -OnOutputLine { param($line) Write-Log $line } `
        -CurrentProcessRef ([ref]$script:currentProc)

    Show-FormInForeground -Form $form

    if ($exitCode -ne 0) {
        Write-Log "--------------- $(Get-BatchDisplayLabel -ButtonDef $ButtonDef) 失敗（終了コード: $exitCode） ---------------"
    } else {
        Write-Log "--------------- $(Get-BatchDisplayLabel -ButtonDef $ButtonDef) 完了 ---------------"
    }

    return $exitCode
}

function Invoke-BatchRunAll {
    Set-RunButtonsEnabled $false
    foreach ($chk in $script:batchStepCheckboxes) { $chk.Enabled = $false }
    $lblBatchStatus.ForeColor = [System.Drawing.Color]::Black
    $lblBatchStatus.Text = "実行中..."

    Write-Log ""
    Write-Log "==================== 一括実行 開始 ===================="

    # チェックを外したステップはスキップする。いずれかのステップが失敗しても、
    # 以降のステップは独立した処理のため続行する
    $anyFailed = $false
    for ($i = 0; $i -lt $allButtonDefs.Count; $i++) {
        $bd = $allButtonDefs[$i]
        if (-not $script:batchStepCheckboxes[$i].Checked) {
            Write-Log "$(Get-BatchDisplayLabel -ButtonDef $bd) はチェックが外れているためスキップします。"
            continue
        }
        $exitCode = Invoke-BatchStep -ButtonDef $bd
        if ($exitCode -ne 0) { $anyFailed = $true }
    }

    Write-Log "==================== 一括実行 完了 ===================="

    if ($anyFailed) {
        $lblBatchStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblBatchStatus.Text = "失敗のステップあり"
    } else {
        $lblBatchStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblBatchStatus.Text = "成功"
    }

    foreach ($chk in $script:batchStepCheckboxes) { $chk.Enabled = $true }
    Set-RunButtonsEnabled $true
}

# =========================================
# 実行タブ（カテゴリごとに分割）
# =========================================

$tabResult = New-CategoryTabControl -TabControl $tabControl -CategoryDefs $categoryDefs -OnRunClick { param($bd) Invoke-BatButton -ButtonDef $bd }
$script:runButtons = $tabResult.RunButtons

# 一括実行タブが既定の選択タブになるため、New-CategoryTabControl側で計算済みだった
# 初期の$tabControl.Height（実施データ取得タブ基準）をこのタブの内容量に合わせて上書きする。
# 45はNew-CategoryTabControlの$TabHeaderAllowance既定値
$tabControl.Height = 45 + $batchPanel.Height

# Labelはカテゴリをまたいで重複し得るため、Labelをキーにした辞書からではなく
# ButtonDef自身が持つStepStatusLabelプロパティ（New-CategoryTabControlが設定）を直接使う
function Set-StepStatus {
    param($ButtonDef, [string]$Text)
    $color = switch ($Text) {
        "実行中..." { [System.Drawing.Color]::Black }
        "成功"      { [System.Drawing.Color]::DarkGreen }
        "失敗"      { [System.Drawing.Color]::DarkRed }
        default     { [System.Drawing.Color]::Gray }
    }
    Set-StatusLabelText -Label $ButtonDef.StepStatusLabel -Text $Text -ForeColor $color
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
    Set-ButtonsEnabled -Buttons $script:runButtons -Enabled $Enabled
    Set-ButtonsEnabled -Buttons $script:batchRunButtons -Enabled $Enabled
}

function Invoke-BatButton {
    param($ButtonDef)

    Set-RunButtonsEnabled $false
    Set-StepStatus -ButtonDef $ButtonDef -Text "実行中..."

    Write-Log ""
    Write-Log "--------------- $($ButtonDef.Label) 開始 ---------------"

    $batArgs = @()
    $inputMap = $ButtonDef.InputControls
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
        Set-StepStatus -ButtonDef $ButtonDef -Text "失敗"
    } else {
        Write-Log "--------------- $($ButtonDef.Label) 完了 ---------------"
        Set-StepStatus -ButtonDef $ButtonDef -Text "成功"
    }

    Set-RunButtonsEnabled $true
}

# ps2exeビルド環境ではタブの既定選択がずれることがあるため明示的に指定する
$tabControl.SelectedTab = $tabBatchAll

[System.Windows.Forms.Application]::Run($form)
