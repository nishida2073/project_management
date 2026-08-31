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
$script:suppressComboSync = $false

$clientsDir = Join-Path $rootPath "clients"

# 対象グループの選択肢はclients\直下の*.xlsx（clients\template\は対象外）のファイル名から、
# 末尾の-年度（例: -2026）を除いた名前を重複排除して作る（設定タブと同じ考え方）
function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        if ($baseName -match '^(?<group>.+)-\d{4}$') { $Matches['group'] } else { $baseName }
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

# 対象グループの入力欄は「すべて」（値は空文字）＋実在するグループ名。各batは
# %TargetGroupNameFilter%*.xlsxという接頭語一致のグロブで絞り込むため、空文字なら全グループが対象になる
$groupOptions = @([PSCustomObject]@{ Text = "すべて"; Value = "" })
foreach ($groupName in (Get-GroupNames)) {
    $groupOptions += [PSCustomObject]@{ Text = $groupName; Value = $groupName }
}
function New-TargetGroupInput {
    param([bool]$NewRow = $false)
    [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象グループ"; Default = ""; LabelWidth = 75; InputWidth = 150; Options = $groupOptions; NewRow = $NewRow }
}

# GUIのタブ（カテゴリ）とその中に並べるボタンの定義。並べ方や見た目はNew-CategoryTabControl側の責務
$categoryDefs = @(
    [PSCustomObject]@{
        Label = "実施データ取得"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施データ取得-テスト・アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "download-results.bat"); TargetDirPath = $script:commonEnvVars["ClientDataRootDir"]; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "取得状況確認"; BatchLabel = "実施データ取得-取得状況確認"; IncludeInBatch = $false; BatchPath = (Join-Path $basePath "check-download-status.bat"); TargetDirPath = $script:commonEnvVars["ResultRootDir"]; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "実施状況確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施状況確認-テスト・アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-combine-result.bat"); TargetDirPath = $script:commonEnvVars["OutputCombineCollectDir"]; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "実施結果確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト"; BatchLabel = "実施結果確認-テスト"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-test-result.bat"); TargetDirPath = $script:commonEnvVars["OutputTestCollectDir"]; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "アンケート"; BatchLabel = "実施結果確認-アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-survey-result.bat"); TargetDirPath = $script:commonEnvVars["OutputSurveyCollectDir"]; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "経年比較"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "アンケート・テスト"
                BatchLabel = "経年比較-アンケート・テスト"
                IncludeInBatch = $true
                BatchPath = (Join-Path $basePath "collect-year-comparison-result.bat")
                TargetDirPath = $script:commonEnvVars["OutputYearComparisonCollectDir"]
                Inputs = @(
                    (New-TargetGroupInput)
                    [PSCustomObject]@{ Name = "TargetCompanyNames"; Label = "対象の会社名"; Default = $script:commonEnvVars["TargetCompanyNames"]; LabelWidth = 85; InputWidth = 260; NewRow = $true }
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

# 対象グループ（共通入力）。各ボタン固有の入力欄（経年比較集計のTargetCompanyNames等）は
# ボタンごとに異なるため一括実行タブには置かないが、対象グループの絞り込みだけは全ボタン共通の
# 概念のため、ここに1つだけ置いて全ステップに適用する（Invoke-BatchStep参照）
$lblBatchGroup = New-Object System.Windows.Forms.Label
$lblBatchGroup.Text = "対象グループ"
$lblBatchGroup.AutoSize = $true

$cmbBatchGroup = New-Object System.Windows.Forms.ComboBox
$cmbBatchGroup.Size = New-Object System.Drawing.Size(150, 24)
$cmbBatchGroup.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbBatchGroup.DisplayMember = "Text"
foreach ($opt in $groupOptions) { $cmbBatchGroup.Items.Add($opt) | Out-Null }
if ($cmbBatchGroup.Items.Count -gt 0) { $cmbBatchGroup.SelectedIndex = 0 }

$batchTopControls = @()

# ステップごとのチェックボックス＋開くリンク（チェックを外したステップは「一括実行」の対象外になる）。
# このツールはボタンごとに入力欄の内容が異なり（経年比較集計だけが専用の入力欄を持つ）、
# 全ボタン共通の入力欄は対象グループのみのため、一括実行タブにはそれ以外の入力欄を置かない。
# チェックボックスはLabelではなく$allButtonDefsと同じ並び順のインデックスで対応付ける
# （Labelはカテゴリをまたいで重複し得るため、Labelをキーにするとハッシュテーブルで
# 上書きが起きてチェック状態を取り違える）
$script:batchStepCheckboxes = @()
$y = 56
foreach ($bd in $allButtonDefs) {
    # common-env.bat由来の空でない既定値を持つInputs（経年比較集計のComparePeriod等）は
    # 一括実行タブで値を確認・変更できないまま実行されてしまうため、既定はチェックを外しておく。
    # 一方、対象グループの絞り込み（既定は空欄＝全グループ）のように既定値が常に空のInputsは、
    # チェックを外さなくても安全に一括実行できるため対象外にする
    $hasNonEmptyInputDefault = @($bd.Inputs | Where-Object { $_.Default }).Count -gt 0
    # BatchLabelの長さはボタンごとに異なるため、AutoSizeで実測幅に合わせると「開く」の位置が
    # ずれて見切れたり画面外に出たりする。チェックボックスを固定幅＋省略表示にして「開く」の位置を固定する
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = Get-BatchDisplayLabel -ButtonDef $bd
    $chk.Checked = if ($hasNonEmptyInputDefault) { $false } else { $true }
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

$batchTopControls += @($lblBatchGroup, $cmbBatchGroup)
$batchPanel.Controls.AddRange($batchTopControls)
$batchPanel.Height = $y + 10 + 28 + 16

# Label/ComboBoxは親に追加された後でないと実際のHeightが確定しないため、
# Controls.AddRangeの後で縦中央揃えのY位置を計算する（設定タブの対象行と同じ理由）
$batchGroupRowCenterY = 26
$lblBatchGroup.Location = New-Object System.Drawing.Point(20, ($batchGroupRowCenterY - [int]($lblBatchGroup.Height / 2)))
$cmbBatchGroup.Location = New-Object System.Drawing.Point(100, ($batchGroupRowCenterY - [int]($cmbBatchGroup.Height / 2)))

$btnRunAll.Add_Click({ Invoke-BatchRunAll })

# 一括実行タブでの1ステップ分の実行本体（「一括実行」から順番に呼ばれる）
function Invoke-BatchStep {
    param($ButtonDef)

    Write-Log ""
    Write-Log "--------------- $(Get-BatchDisplayLabel -ButtonDef $ButtonDef) 開始 ---------------"

    # 一括実行タブには対象グループ以外の個別タブのような専用入力欄が無いため、
    # 対象グループ以外のInputs（経年比較集計のTargetCompanyNames等）はcommon-env.bat由来の
    # 既定値（Default）をそのまま使う。対象グループだけは一括実行タブの共通入力欄の値を使う
    $batArgs = @()
    foreach ($inputDef in $ButtonDef.Inputs) {
        $value = if ($inputDef.Name -eq "TargetGroupNameFilter") { Get-InputValue -Control $cmbBatchGroup } else { $inputDef.Default }
        $batArgs += "$($inputDef.Name):$value"
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

# =========================================
# 設定タブ（kintone-aggregatorの設定タブと同様のレイアウト：
# 対象を切り替えて共通設定/グループ別設定を編集する）
#
# 「共通設定」はcommon-env.bat（対象年度に関わらず共通のパス・既定値設定）を直接編集する。
# グループを選ぶと、そのグループのclients\<グループ名>.bat（認証情報）を編集する。
# kintone-aggregatorと異なり、このツールには業務日誌・パルスサーベイのような複数種別のマッピング
# ファイルは無く、グループごとの設定はclients\<グループ名>.bat 1本のみ。
# 受講生データ（xlsx）はclients\<グループ名>-<年度>.xlsxという年度別ファイルのため、
# グループ一覧は末尾の-年度を除いた名前で重複排除して作る（resolve-env-file.batの
# 「年度を除いた名前で.batを探す」ロジックと同じ考え方）。
# 新規グループはclients\template\の内容を初期値として使う（保存するまでファイルは作成しない）
# =========================================

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "設定"
$tabControl.Controls.Add($tabSettings)

$clientsDir = Join-Path $rootPath "clients"
$clientsTemplateDir = Join-Path $clientsDir "template"
$defaultSettingsLabel = "共通設定"
$settingsLineRegex = [regex]'^set "(?<var>\S+?)=(?<val>.*)"$'

function Get-GroupBatPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.bat" }
function Get-GroupXlsxPath { param([string]$GroupName, [string]$Year) Join-Path $clientsDir "$GroupName-$Year.xlsx" }

# グループ名に一致する受講生データ（xlsx）を探す。<グループ名>.xlsxと<グループ名>-<年度>.xlsxの
# どちらも対象（resolve-env-file.batが.batを探すときの対応関係と同じ）
function Get-GroupXlsxFiles {
    param([string]$GroupName)
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $escaped = [regex]::Escape($GroupName)
    return @(Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | Where-Object {
        $_.BaseName -eq $GroupName -or $_.BaseName -match "^${escaped}-\d{4}$"
    })
}

# clients\template\直下の受講生データテンプレート（client-<年度>.xlsxという名前）を1件探す
function Get-TemplateXlsxPath {
    $found = Get-ChildItem -LiteralPath $clientsTemplateDir -Filter "client*.xlsx" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

# set "VAR=value" 形式の行だけを拾ってVAR→valueのハッシュテーブルにする（common-env.bat・グループ別ファイル共通）
function Get-SetLineRawValues {
    param([string]$Path)
    $result = @{}
    if (!(Test-Path -LiteralPath $Path)) { return $result }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, $script:cp932Encoding)) {
        $m = $settingsLineRegex.Match($line.Trim())
        if ($m.Success) { $result[$m.Groups["var"].Value] = $m.Groups["val"].Value }
    }
    return $result
}

# TargetYearはcommon-env.bat内でpowershellコマンドから動的に計算される特殊な行（set "VAR=value"形式
# ではない）ため、このリストにも$settingsLineRegexにも掛からず編集対象にならない（既存の行はそのまま保持される）
$commonSettingsVars = @(
    "ClientDataRootDir", "TemplateRootDir", "LOG_DIR",
    "ResultRootDir", "TestResultRootDir", "SurveyResultRootDir",
    "OutputRootDir", "OutputTestCollectDir", "OutputTestResultFileSuffix", "OutputSurveyCollectDir", "OutputSurveyResultFileSuffix", "OutputCombineCollectDir", "OutputCombineResultFileSuffix", "OutputYearComparisonCollectDir", "OutputYearComparisonResultFileSuffix",
    "PassScore",
    "AutoHotkeyExePath", "AutoHotkeyScriptPath", "TrackLoginUrl",
    "ComparePeriod",
    "CourseGroupDefs",
    "YearOrder"
)
$authVars = @("KintoneSubdomain")
# 共通設定（common-env.bat）の既定値をグループ単位で上書きしたい項目。
# clients\<グループ名>.batはcommon-env.batの後にcallされるため、ここで値を書けばそのグループだけ上書きされる。
# 空欄のまま保存した場合はこの3行自体を書き出さない（空文字を上書きしてしまうと共通設定側の値が
# 効かなくなるため、「未指定＝共通設定の値を使う」を「行を書かない」で表す）
$groupOverrideVars = @("ComparePeriod", "YearOrder", "PassScore")

$settingsGroupLabels = @{ "COMMON" = "共通設定"; "AUTH" = "認証情報"; "OVERRIDE" = "個別設定（空欄の場合は共通設定の値を使用）" }
$settingsVarLabels = @{
    "ClientDataRootDir"               = "受講生データのフォルダ"
    "TemplateRootDir"                 = "テンプレートのフォルダ"
    "LOG_DIR"                         = "ログの出力先"
    "ResultRootDir"                   = "実施結果の取得先（共通）"
    "TestResultRootDir"               = "テスト結果の取得先"
    "SurveyResultRootDir"             = "アンケート結果の取得先"
    "OutputRootDir"                   = "集計結果の出力先（共通）"
    "OutputTestCollectDir"            = "テスト集計結果の出力先"
    "OutputTestResultFileSuffix"      = "テスト結果ファイル名の接尾辞"
    "OutputSurveyCollectDir"          = "アンケート集計結果の出力先"
    "OutputSurveyResultFileSuffix"    = "アンケート結果ファイル名の接尾辞"
    "OutputCombineCollectDir"         = "統合結果の出力先"
    "OutputCombineResultFileSuffix"   = "統合結果ファイル名の接尾辞"
    "OutputYearComparisonCollectDir"  = "経年比較結果の出力先"
    "OutputYearComparisonResultFileSuffix" = "経年比較結果ファイル名の接尾辞"
    "PassScore"                       = "合格点"
    "AutoHotkeyExePath"               = "AutoHotkey実行ファイルのパス"
    "AutoHotkeyScriptPath"            = "ダウンロード用スクリプトのパス"
    "TrackLoginUrl"                   = "trackログインURL"
    "ComparePeriod"                   = "経年比較の比較年数"
    "CourseGroupDefs"                 = "コースグループ定義"
    "YearOrder"                       = "経年比較の年度表示順（0:昇順 1:降順）"
    "KintoneSubdomain"                = "kintoneサブドメイン"
}
$settingsFolderBrowseVars = @(
    "ClientDataRootDir", "TemplateRootDir", "LOG_DIR",
    "ResultRootDir", "TestResultRootDir", "SurveyResultRootDir",
    "OutputRootDir", "OutputTestCollectDir", "OutputSurveyCollectDir", "OutputCombineCollectDir", "OutputYearComparisonCollectDir"
)

# clients\template\client.batの内容（グループ新規作成時の初期値）。一度だけ読み込みキャッシュする
$script:groupTemplateDefaults = $null
function Get-GroupTemplateDefaults {
    if ($null -eq $script:groupTemplateDefaults) {
        $script:groupTemplateDefaults = [PSCustomObject]@{
            Auth = Get-SetLineRawValues -Path (Join-Path $clientsTemplateDir "client.bat")
        }
    }
    return $script:groupTemplateDefaults
}

$settingsTopPanel = New-Object System.Windows.Forms.Panel
$settingsTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$settingsTopPanel.Height = 70

$lblSettingsTarget = New-Object System.Windows.Forms.Label
$lblSettingsTarget.Text = "対象"
$lblSettingsTarget.AutoSize = $true

$cmbSettingsTarget = New-Object System.Windows.Forms.ComboBox
$cmbSettingsTarget.Size = New-Object System.Drawing.Size(260, 24)
$cmbSettingsTarget.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$btnSettingsNewGroup = New-Object System.Windows.Forms.Button
$btnSettingsNewGroup.Text = "新規作成"
$btnSettingsNewGroup.Size = New-Object System.Drawing.Size(140, 24)

$lnkSettingsOpenXlsx = New-Object System.Windows.Forms.LinkLabel
$lnkSettingsOpenXlsx.Text = "開く"
$lnkSettingsOpenXlsx.AutoSize = $true

$btnSettingsSave = New-Object System.Windows.Forms.Button
$btnSettingsSave.Text = "保存"
$btnSettingsSave.Location = New-Object System.Drawing.Point(20, 44)
$btnSettingsSave.Size = New-Object System.Drawing.Size(100, 24)

$btnSettingsReload = New-Object System.Windows.Forms.Button
$btnSettingsReload.Text = "再読込"
$btnSettingsReload.Location = New-Object System.Drawing.Point(130, 44)
$btnSettingsReload.Size = New-Object System.Drawing.Size(100, 24)

$lblSettingsSaveStatus = New-Object System.Windows.Forms.Label
$lblSettingsSaveStatus.Text = ""
$lblSettingsSaveStatus.AutoSize = $true
$lblSettingsSaveStatus.Location = New-Object System.Drawing.Point(244, 50)
$lblSettingsSaveStatus.Font = New-Object System.Drawing.Font($lblSettingsSaveStatus.Font, [System.Drawing.FontStyle]::Bold)

$settingsTopPanel.Controls.AddRange(@($lblSettingsTarget, $cmbSettingsTarget, $btnSettingsNewGroup, $lnkSettingsOpenXlsx, $btnSettingsSave, $btnSettingsReload, $lblSettingsSaveStatus))

# Label/LinkLabelはAutoSizeによる実際のHeightが親へのAddより前だと仮の値のままで、
# 親に追加された後でないと正しい値に確定しない。TextBox/ComboBoxも指定したHeightを
# 無視してフォントに応じた高さに強制されるため、いずれもControls.Addの後で実際のHeightを見て
# Y位置を計算しないと縦の中央が揃わない（New-CategoryTabControlの入力欄と同じ理由）
$settingsRow1CenterY = 26
$lblSettingsTarget.Location = New-Object System.Drawing.Point(20, ($settingsRow1CenterY - [int]($lblSettingsTarget.Height / 2)))
$cmbSettingsTarget.Location = New-Object System.Drawing.Point(90, ($settingsRow1CenterY - [int]($cmbSettingsTarget.Height / 2)))
$btnSettingsNewGroup.Location = New-Object System.Drawing.Point(360, ($settingsRow1CenterY - [int]($btnSettingsNewGroup.Height / 2)))
$lnkSettingsOpenXlsx.Location = New-Object System.Drawing.Point(510, ($settingsRow1CenterY - [int]($lnkSettingsOpenXlsx.Height / 2)))

$settingsFieldPanel = New-Object System.Windows.Forms.Panel
$settingsFieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsFieldPanel.AutoScroll = $true

$tabSettings.Controls.Add($settingsFieldPanel)
$tabSettings.Controls.Add($settingsTopPanel)

$settingsToolTip = New-Object System.Windows.Forms.ToolTip

# グループ一覧はclients\直下の*.xlsx（clients\template\は対象外）のファイル名から、
# 末尾の-年度（例: -2026）を除いた名前を重複排除して作る
function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        if ($baseName -match '^(?<group>.+)-\d{4}$') { $Matches['group'] } else { $baseName }
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

function Update-SettingsGroupList {
    $selected = $cmbSettingsTarget.SelectedItem
    $script:suppressComboSync = $true
    $cmbSettingsTarget.Items.Clear()
    $cmbSettingsTarget.Items.Add($defaultSettingsLabel) | Out-Null
    foreach ($groupName in (Get-GroupNames)) {
        $cmbSettingsTarget.Items.Add($groupName) | Out-Null
    }
    $cmbSettingsTarget.SelectedIndex = if ($selected -and $cmbSettingsTarget.Items.Contains($selected)) { $cmbSettingsTarget.Items.IndexOf($selected) } else { 0 }
    $script:suppressComboSync = $false
}

function Get-SettingsFieldRows {
    $target = $cmbSettingsTarget.SelectedItem
    if (!$target -or $target -eq $defaultSettingsLabel) {
        $raw = Get-SetLineRawValues -Path (Join-Path $basePath "common-env.bat")
        foreach ($varName in $commonSettingsVars) {
            [PSCustomObject]@{ Key = $varName; VarName = $varName; Group = "COMMON"; Value = $raw[$varName] }
        }
        return
    }

    $templateDefaults = Get-GroupTemplateDefaults
    $rawAuth = Get-SetLineRawValues -Path (Get-GroupBatPath $target)
    foreach ($varName in $authVars) {
        $value = if ($rawAuth.ContainsKey($varName)) { $rawAuth[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "AUTH_$varName"; VarName = $varName; Group = "AUTH"; Value = $value }
    }
    # 上書き項目は共通設定・テンプレートの値にはフォールバックしない。「空欄」がそのまま
    # 「このグループでは上書きしていない」を表す（Save-GroupSettings側も参照）
    foreach ($varName in $groupOverrideVars) {
        $value = if ($rawAuth.ContainsKey($varName)) { $rawAuth[$varName] } else { "" }
        [PSCustomObject]@{ Key = "OVERRIDE_$varName"; VarName = $varName; Group = "OVERRIDE"; Value = $value }
    }
}

$script:settingsFieldTextBoxes = @{}

function Update-SettingsFields {
    $settingsFieldPanel.Controls.Clear()
    $script:settingsFieldTextBoxes = @{}

    $y = 10
    $lastGroup = ""
    foreach ($field in (Get-SettingsFieldRows)) {
        if ($field.Group -ne $lastGroup) {
            if ($lastGroup -ne "") {
                $y += 10
                $separator = New-Object System.Windows.Forms.Panel
                $separator.BackColor = [System.Drawing.Color]::LightGray
                $separator.Location = New-Object System.Drawing.Point(10, $y)
                $separator.Size = New-Object System.Drawing.Size(690, 2)
                $settingsFieldPanel.Controls.Add($separator)
                $y += 14
            }
            $lblGroup = New-Object System.Windows.Forms.Label
            $lblGroup.Text = $settingsGroupLabels[$field.Group]
            $lblGroup.AutoSize = $true
            $lblGroup.Location = New-Object System.Drawing.Point(10, $y)
            $lblGroup.Font = New-Object System.Drawing.Font($lblGroup.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold)
            $settingsFieldPanel.Controls.Add($lblGroup)
            $y += 28
            $lastGroup = $field.Group
        }

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = if ($settingsVarLabels.ContainsKey($field.VarName)) { $settingsVarLabels[$field.VarName] } else { $field.VarName }
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size(220, 20)
        $lbl.Location = New-Object System.Drawing.Point(20, $y)
        $settingsToolTip.SetToolTip($lbl, $field.VarName)
        $settingsFieldPanel.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Text = "$($field.Value)"
        $txt.Location = New-Object System.Drawing.Point(250, ($y - 2))
        $txt.Size = New-Object System.Drawing.Size(300, 22)
        $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
        $settingsFieldPanel.Controls.Add($txt)

        if ($settingsFolderBrowseVars -contains $field.VarName) {
            $btnBrowse = New-Object System.Windows.Forms.Button
            $btnBrowse.Text = "参照..."
            $btnBrowse.Location = New-Object System.Drawing.Point(560, ($y - 3))
            $btnBrowse.Size = New-Object System.Drawing.Size(70, 24)
            $btnBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $btnBrowse.Tag = $txt
            $btnBrowse.Add_Click({
                $targetTxt = $this.Tag
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                if ($targetTxt.Text -and (Test-Path -LiteralPath $targetTxt.Text)) { $dlg.SelectedPath = $targetTxt.Text }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $targetTxt.Text = $dlg.SelectedPath }
            })
            $settingsFieldPanel.Controls.Add($btnBrowse)
        }

        $script:settingsFieldTextBoxes[$field.Key] = $txt
        $y += 28
    }
}

function Get-SettingsFieldValue {
    param([string]$Key)
    return $script:settingsFieldTextBoxes[$Key].Text
}

function Save-CommonSettings {
    $path = Join-Path $basePath "common-env.bat"
    $newLines = foreach ($line in [System.IO.File]::ReadAllLines($path, $script:cp932Encoding)) {
        $m = $settingsLineRegex.Match($line.Trim())
        if ($m.Success -and ($commonSettingsVars -contains $m.Groups["var"].Value)) {
            $varName = $m.Groups["var"].Value
            $val = Get-SettingsFieldValue $varName
            "set `"$varName=$val`""
        } else {
            $line
        }
    }
    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($path, $content, $script:cp932Encoding)
}

function Save-GroupSettings {
    param([string]$GroupName)

    $subdomainValue = Get-SettingsFieldValue "AUTH_KintoneSubdomain"
    # BaseUrlは画面では編集させず、KintoneSubdomainから常に導出する
    $authLines = @("@echo off", "", "set `"KintoneSubdomain=$subdomainValue`"", "set `"BaseUrl=https://%KintoneSubdomain%.cybozu.com`"")

    # 上書き項目は空欄なら行自体を書かない（空文字を上書きすると共通設定側の値が効かなくなるため）
    foreach ($varName in $groupOverrideVars) {
        $val = Get-SettingsFieldValue "OVERRIDE_$varName"
        if ($val -ne "") { $authLines += "set `"$varName=$val`"" }
    }
    $authLines += ""
    [System.IO.File]::WriteAllText((Get-GroupBatPath $GroupName), (($authLines -join "`r`n") + "`r`n"), $script:cp932Encoding)

    # 受講生データ（xlsx）は既存グループでは何もしない。新規グループのときだけ、
    # common-env.bat側のTargetYear（対象年度）に合わせてclients\template\からコピーする
    if ((Get-GroupXlsxFiles -GroupName $GroupName).Count -eq 0) {
        $currentYear = $script:commonEnvVars["TargetYear"]
        $templateXlsxPath = Get-TemplateXlsxPath
        if ($currentYear -and $templateXlsxPath) {
            Copy-Item -LiteralPath $templateXlsxPath -Destination (Get-GroupXlsxPath $GroupName $currentYear)
        }
    }
}

$btnSettingsSave.Add_Click({
    $target = $cmbSettingsTarget.SelectedItem
    if (!$target -or $target -eq $defaultSettingsLabel) {
        Save-CommonSettings
    } else {
        Save-GroupSettings -GroupName $target
    }
    Update-SettingsGroupList
    Update-SettingsFields
    $lblSettingsSaveStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblSettingsSaveStatus.Text = "保存しました"
})

$btnSettingsReload.Add_Click({
    Update-SettingsFields
    $lblSettingsSaveStatus.ForeColor = [System.Drawing.Color]::Black
    $lblSettingsSaveStatus.Text = "再読込しました"
})

$btnSettingsNewGroup.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("グループ名を入力してください", "グループの新規作成", "")
    $newName = $newName.Trim()
    if (!$newName) { return }

    if ($cmbSettingsTarget.Items.Contains($newName) -or (Get-GroupXlsxFiles -GroupName $newName).Count -gt 0 -or (Test-Path -LiteralPath (Get-GroupBatPath $newName))) {
        [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "グループの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $cmbSettingsTarget.Items.Add($newName) | Out-Null
    $cmbSettingsTarget.SelectedItem = $newName
})

$lnkSettingsOpenXlsx.Add_LinkClicked({
    $target = $cmbSettingsTarget.SelectedItem
    if (!$target -or $target -eq $defaultSettingsLabel) {
        [System.Windows.Forms.MessageBox]::Show("共通設定には受講生データがありません。", "受講生データを開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    # 同じグループで複数年度のファイルがあり得るため、対象年度（TargetYear）のファイルを優先し、
    # 無ければ最も更新日時が新しいものを開く
    $currentYear = $script:commonEnvVars["TargetYear"]
    $openPath = $null
    if ($currentYear) {
        $currentYearPath = Get-GroupXlsxPath $target $currentYear
        if (Test-Path -LiteralPath $currentYearPath) { $openPath = $currentYearPath }
    }
    if (!$openPath) {
        $latest = Get-GroupXlsxFiles -GroupName $target | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $openPath = $latest.FullName }
    }
    if (!$openPath) { $openPath = Get-GroupXlsxPath $target $currentYear }
    Open-FolderOrWarn -Path $openPath
})

$cmbSettingsTarget.Add_SelectedIndexChanged({
    if (!$script:suppressComboSync) { Update-SettingsFields }
})

# 設定タブは実行結果を伴わないため共通ログ欄が不要。設定タブ選択時だけログ欄を隠し、
# その分タブの表示領域を広げる（他のタブでは高さ計算をNew-CategoryTabControl側の
# $updateTabHeight closureに任せているため、ここでは触らない）
$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabSettings) {
        Update-SettingsGroupList
        $logSpacer.Visible = $false
        $txtLog.Visible = $false
        $tabControl.Height = $form.ClientSize.Height
    } else {
        $logSpacer.Visible = $true
        $txtLog.Visible = $true
    }
}.GetNewClosure())

Update-SettingsGroupList
Update-SettingsFields

# ps2exeビルド環境ではタブの既定選択がずれることがあるため明示的に指定する
$tabControl.SelectedTab = $tabBatchAll

[System.Windows.Forms.Application]::Run($form)
