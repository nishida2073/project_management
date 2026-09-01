# =========================================
# GUI（kintoneデータ集計ツール）
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

# 対象グループの選択肢はclients\直下の*.xlsx（clients\template\は対象外）のファイル名から作る。
# 実行対象の判定（%TargetGroupNameFilter%.xlsx）と同じ考え方
function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
}

# 空欄（すべて）を選ぶと各batが内部でTargetGroupNameFilter=*（全グループ）として扱う
$groupOptions = @([PSCustomObject]@{ Text = "すべて"; Value = "" })
foreach ($groupName in (Get-GroupNames)) {
    $groupOptions += [PSCustomObject]@{ Text = $groupName; Value = $groupName }
}

# 日付入力の既定値は当日（対象グループが空欄の場合のみ各batが内部で全グループとして扱う）
$defaultTargetDate = (Get-Date).ToString("yyyy-MM-dd")
$dateAndGroupInputs = @(
    [PSCustomObject]@{ Name = "TargetDate"; Label = "対象日"; Default = $defaultTargetDate; LabelWidth = 55; InputWidth = 90 }
    [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象グループ"; Default = ""; LabelWidth = 75; InputWidth = 120; Options = $groupOptions }
)
$dateOnlyInputs = @(
    [PSCustomObject]@{ Name = "TargetDate"; Label = "対象日"; Default = $defaultTargetDate; LabelWidth = 55; InputWidth = 90 }
)

# GUIのタブ（カテゴリ）とその中に並べるボタンの定義。並べ方や見た目はNew-CategoryTabControl側の責務
$categoryDefs = @(
    [PSCustomObject]@{
        Label = "アプリデータ作成"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌"; BatchLabel = "アプリデータ作成-業務日誌"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "create-daily-report.bat"); TargetDirPath = $script:commonEnvVars["OutputReportDir"]; Inputs = $dateAndGroupInputs }
            [PSCustomObject]@{ Label = "パルスサーベイ"; BatchLabel = "アプリデータ作成-パルスサーベイ"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "create-pulse-survey.bat"); TargetDirPath = $script:commonEnvVars["OutputReportDir"]; Inputs = $dateAndGroupInputs }
        )
    }
    [PSCustomObject]@{
        Label = "アプリデータ集計"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌・パルスサーベイ"; BatchLabel = "アプリデータ集計-業務日誌・パルスサーベイ"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-app-data.bat"); TargetDirPath = $script:commonEnvVars["OutputCollectDataRootDir"]; Inputs = $dateAndGroupInputs }
        )
    }
    [PSCustomObject]@{
        Label = "アラート集計"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌・パルスサーベイ"; BatchLabel = "アラート集計-業務日誌・パルスサーベイ"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "check-alert.bat"); TargetDirPath = $script:commonEnvVars["OutputAlertRootDir"]; Inputs = $dateAndGroupInputs }
        )
    }
)

$form = New-Object System.Windows.Forms.Form
$form.Text = "kintoneデータ集計ツール"
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
# チェックボックスで対象ステップを選び、共通入力欄を使って1つの実行ボタンで一括実行する）
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

# 共通入力（対象日・対象グループ）
$lblBatchDate = New-Object System.Windows.Forms.Label
$lblBatchDate.Text = "対象日"
$lblBatchDate.AutoSize = $true
$lblBatchDate.Location = New-Object System.Drawing.Point(20, 17)

$txtBatchDate = New-Object System.Windows.Forms.TextBox
$txtBatchDate.Location = New-Object System.Drawing.Point(80, 14)
$txtBatchDate.Size = New-Object System.Drawing.Size(90, 24)
$txtBatchDate.Text = $defaultTargetDate

$lblBatchGroup = New-Object System.Windows.Forms.Label
$lblBatchGroup.Text = "対象グループ"
$lblBatchGroup.AutoSize = $true
$lblBatchGroup.Location = New-Object System.Drawing.Point(190, 17)

$cmbBatchGroup = New-Object System.Windows.Forms.ComboBox
$cmbBatchGroup.Location = New-Object System.Drawing.Point(280, 14)
$cmbBatchGroup.Size = New-Object System.Drawing.Size(120, 24)
$cmbBatchGroup.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbBatchGroup.DisplayMember = "Text"
foreach ($opt in $groupOptions) { $cmbBatchGroup.Items.Add($opt) | Out-Null }
if ($cmbBatchGroup.Items.Count -gt 0) { $cmbBatchGroup.SelectedIndex = 0 }

$script:batchInputControls = @{
    TargetDate            = $txtBatchDate
    TargetGroupNameFilter = $cmbBatchGroup
}

$batchTopControls = @($lblBatchDate, $txtBatchDate, $lblBatchGroup, $cmbBatchGroup)

# ステップごとのチェックボックス＋開くリンク（チェックを外したステップは「一括実行」の対象外になる）。
# チェックボックスはLabelではなく$allButtonDefsと同じ並び順のインデックスで対応付ける
# （Labelはカテゴリをまたいで重複し得るため、Labelをキーにするとハッシュテーブルで
# 上書きが起きてチェック状態を取り違える）
$script:batchStepCheckboxes = @()
$y = 46
foreach ($bd in $allButtonDefs) {
    # BatchLabelを指定したButtonDefだけ、一括実行タブでの表示名を実行タブ側のLabelと切り離せる。
    # BatchLabelの長さはボタンごとに異なるため、AutoSizeで実測幅に合わせると「開く」の位置がずれて
    # 見切れたり画面外に出たりする。チェックボックスを固定幅＋省略表示にして「開く」の位置を固定する
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = Get-BatchDisplayLabel -ButtonDef $bd
    $chk.Checked = $true
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

    # 一括実行タブでは、個別タブのようなボタンごとの専用入力欄ではなく、
    # このタブ内の共通入力欄（対象日・対象グループ）から値を取得する
    $batArgs = @()
    foreach ($inputDef in $ButtonDef.Inputs) {
        $batArgs += Get-InputValue -Control $script:batchInputControls[$inputDef.Name]
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
    foreach ($inputCtrl in $script:batchInputControls.Values) { $inputCtrl.Enabled = $false }
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
    foreach ($inputCtrl in $script:batchInputControls.Values) { $inputCtrl.Enabled = $true }
    Set-RunButtonsEnabled $true
}

# =========================================
# 実行タブ（カテゴリごとに分割）
# =========================================

$tabResult = New-CategoryTabControl -TabControl $tabControl -CategoryDefs $categoryDefs -OnRunClick { param($bd) Invoke-BatButton -ButtonDef $bd }
$script:runButtons = $tabResult.RunButtons

# 一括実行タブが既定の選択タブになるため、New-CategoryTabControl側で計算済みだった
# 初期の$tabControl.Height（アプリデータ作成タブ基準）をこのタブの内容量に合わせて上書きする。
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

    # 各batは位置引数（対象日, 対象グループ）を取るため、Inputsの定義順のまま値を並べて渡す
    $batArgs = @()
    $inputMap = $ButtonDef.InputControls
    if ($inputMap) {
        foreach ($inputDef in $ButtonDef.Inputs) {
            $batArgs += Get-InputValue -Control $inputMap[$inputDef.Name]
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
# 設定タブ（package-generatorの設定タブUIを参考にしたレイアウト：
# 「共通」「グループ別」のサブタブに分けて編集する）
#
# 「共通」タブはcommon-env.bat（対象日・対象グループに関わらず共通のパス設定に加え、
# 全グループ共通の業務日誌/パルスサーベイのフィールドコード）を直接編集する。
# 「グループ別」タブはグループを選ぶと、そのグループのclients\<グループ名>.bat（認証情報＋
# 業務日誌/パルスサーベイの対象アプリID。業務日誌側/パルスサーベイ側それぞれcommon-env.batの
# DailyReportSuffix/PulseSurveySuffixを付けた変数名で1ファイルにまとめて持つ）を編集する。
# 新規グループはclients\template\の内容を初期値として使う（保存するまでファイルは作成しない）
# =========================================

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "設定"
$tabControl.Controls.Add($tabSettings)

$clientsTemplateDir = Join-Path $clientsDir "template"
$settingsLineRegex = [regex]'^set "(?<var>\S+?)=(?<val>.*)"$'

function Get-GroupBatPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.bat" }
function Get-GroupXlsxPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.xlsx" }

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

# 設定タブの各フィールドの生の値には、common-env.bat内の%BASE_PATH%や%OutputRootDir%のような
# %VAR%トークンがそのまま残っている（%~dp0のようなバッチ専用トークンは.NET側では解決できないため、
# common-env.bat側は%BASE_PATH%を使う方式に統一済み）。$script:commonEnvVars（起動時に
# common-env.batを実際に実行して解決済みの値）を使って再帰的に展開する
function Expand-VarTokens {
    param([string]$Value)
    if (!$Value) { return $Value }
    return [regex]::Replace($Value, '%(\w+)%', {
        param($match)
        $refVal = $script:commonEnvVars[$match.Groups[1].Value]
        if ($refVal) { $refVal } else { $match.Value }
    })
}

function Resolve-BrowseStart {
    param([string]$RawValue)
    if (!$RawValue) { return $rootPath }
    return Expand-VarTokens $RawValue
}

$commonSettingsVars = @("ClientDataRootDir", "OutputRootDir", "TemplateRootDir", "LOG_DIR", "OutputReportDir", "OutputCollectDataRootDir", "OutputAlertRootDir")
$authVars = @("KintoneSubdomain", "KintoneID", "KintonePW")

$groupReportVars = @("TargetAppIds")
$commonReportVars = @("TargetDateCodeField", "TargetUserCodeField")

$dailyReportSuffix = $script:commonEnvVars["DailyReportSuffix"]
$pulseSurveySuffix = $script:commonEnvVars["PulseSurveySuffix"]

$settingsGroupLabels = @{ "BASE" = "基本設定"; "AUTH" = "認証情報"; "DAILY" = "業務日誌"; "PULSE" = "パルスサーベイ" }
$settingsVarLabels = @{
    "ClientDataRootDir"        = "グループデータのフォルダ"
    "OutputRootDir"            = "出力のルートフォルダ"
    "TemplateRootDir"          = "テンプレートのフォルダ"
    "LOG_DIR"                  = "ログの出力先"
    "OutputReportDir"          = "業務日誌・パルスサーベイの出力先"
    "OutputCollectDataRootDir" = "アプリデータ集計の出力先"
    "OutputAlertRootDir"       = "アラート検知結果の出力先"
    "KintoneID"                = "kintoneログインID"
    "KintonePW"                = "kintoneログインパスワード"
    "KintoneSubdomain"         = "kintoneサブドメイン"
    "TargetAppIds"             = "対象アプリID"
    "TargetDateCodeField"      = "日付フィールドコード"
    "TargetUserCodeField"      = "受講生IDフィールドコード"
}
$settingsFolderBrowseVars = @("ClientDataRootDir", "OutputRootDir", "TemplateRootDir", "LOG_DIR", "OutputReportDir", "OutputCollectDataRootDir", "OutputAlertRootDir")
$settingsMaskedVars = @("KintonePW")

# TargetAppIds等はdaily-report/pulse-survey双方で同じ変数名を別の値で使うため、変数名に
# $dailyReportSuffix/$pulseSurveySuffixを付けて区別して持つ。この関数はそのサフィックス付きの生値を、
# サフィックスを外した変数名（$VarNamesと同じキー）のハッシュテーブルへ変換する
function Get-SuffixedRawValues {
    param([hashtable]$RawValues, [string]$Suffix, [array]$VarNames)
    $result = @{}
    foreach ($varName in $VarNames) {
        $key = "$varName$Suffix"
        if ($RawValues.ContainsKey($key)) { $result[$varName] = $RawValues[$key] }
    }
    return $result
}

# clients\template\の内容（新規作成の初期値）。一度だけ読み込みキャッシュする。
# グループ別設定（$groupReportVars=TargetAppIds）のみが対象。$commonReportVarsはcommon-env.bat側の
# 共通設定なのでここには含めない
$script:groupTemplateDefaults = $null
function Get-GroupTemplateDefaults {
    if ($null -eq $script:groupTemplateDefaults) {
        $rawTemplate = Get-SetLineRawValues -Path (Join-Path $clientsTemplateDir "client.bat")
        $script:groupTemplateDefaults = [PSCustomObject]@{
            Auth  = $rawTemplate
            Daily = Get-SuffixedRawValues -RawValues $rawTemplate -Suffix $dailyReportSuffix -VarNames $groupReportVars
            Pulse = Get-SuffixedRawValues -RawValues $rawTemplate -Suffix $pulseSurveySuffix -VarNames $groupReportVars
        }
    }
    return $script:groupTemplateDefaults
}

$settingsSubTabControl = New-Object System.Windows.Forms.TabControl
$settingsSubTabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabSettings.Controls.Add($settingsSubTabControl)

$tabSettingsCommon = New-Object System.Windows.Forms.TabPage
$tabSettingsCommon.Text = "共通"
$settingsSubTabControl.Controls.Add($tabSettingsCommon)

$tabSettingsGroup = New-Object System.Windows.Forms.TabPage
$tabSettingsGroup.Text = "グループ別"
$settingsSubTabControl.Controls.Add($tabSettingsGroup)

$settingsToolTip = New-Object System.Windows.Forms.ToolTip

# --- 共通タブ ---
$settingsCommonTopPanel = New-Object System.Windows.Forms.Panel
$settingsCommonTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$settingsCommonTopPanel.Height = 40

$btnSettingsCommonSave = New-Object System.Windows.Forms.Button
$btnSettingsCommonSave.Text = "保存"
$btnSettingsCommonSave.Location = New-Object System.Drawing.Point(20, 8)
$btnSettingsCommonSave.Size = New-Object System.Drawing.Size(100, 24)

$btnSettingsCommonReload = New-Object System.Windows.Forms.Button
$btnSettingsCommonReload.Text = "再読込"
$btnSettingsCommonReload.Location = New-Object System.Drawing.Point(130, 8)
$btnSettingsCommonReload.Size = New-Object System.Drawing.Size(100, 24)

$lblSettingsCommonSaveStatus = New-Object System.Windows.Forms.Label
$lblSettingsCommonSaveStatus.Text = ""
$lblSettingsCommonSaveStatus.AutoSize = $true
$lblSettingsCommonSaveStatus.Location = New-Object System.Drawing.Point(244, 14)
$lblSettingsCommonSaveStatus.Font = New-Object System.Drawing.Font($lblSettingsCommonSaveStatus.Font, [System.Drawing.FontStyle]::Bold)

$settingsCommonTopPanel.Controls.AddRange(@($btnSettingsCommonSave, $btnSettingsCommonReload, $lblSettingsCommonSaveStatus))

$settingsCommonFieldPanel = New-Object System.Windows.Forms.Panel
$settingsCommonFieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsCommonFieldPanel.AutoScroll = $true

$tabSettingsCommon.Controls.Add($settingsCommonFieldPanel)
$tabSettingsCommon.Controls.Add($settingsCommonTopPanel)

# --- グループ別タブ ---
$settingsGroupTopPanel = New-Object System.Windows.Forms.Panel
$settingsGroupTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$settingsGroupTopPanel.Height = 70

$lblSettingsGroupTarget = New-Object System.Windows.Forms.Label
$lblSettingsGroupTarget.Text = "対象"
$lblSettingsGroupTarget.AutoSize = $true

$cmbSettingsGroupTarget = New-Object System.Windows.Forms.ComboBox
$cmbSettingsGroupTarget.Size = New-Object System.Drawing.Size(260, 24)
$cmbSettingsGroupTarget.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$btnSettingsNewGroup = New-Object System.Windows.Forms.Button
$btnSettingsNewGroup.Text = "新規作成"
$btnSettingsNewGroup.Size = New-Object System.Drawing.Size(140, 24)

$lnkSettingsOpenXlsx = New-Object System.Windows.Forms.LinkLabel
$lnkSettingsOpenXlsx.Text = "開く"
$lnkSettingsOpenXlsx.AutoSize = $true

$btnSettingsGroupSave = New-Object System.Windows.Forms.Button
$btnSettingsGroupSave.Text = "保存"
$btnSettingsGroupSave.Location = New-Object System.Drawing.Point(20, 44)
$btnSettingsGroupSave.Size = New-Object System.Drawing.Size(100, 24)

$btnSettingsGroupReload = New-Object System.Windows.Forms.Button
$btnSettingsGroupReload.Text = "再読込"
$btnSettingsGroupReload.Location = New-Object System.Drawing.Point(130, 44)
$btnSettingsGroupReload.Size = New-Object System.Drawing.Size(100, 24)

$lblSettingsGroupSaveStatus = New-Object System.Windows.Forms.Label
$lblSettingsGroupSaveStatus.Text = ""
$lblSettingsGroupSaveStatus.AutoSize = $true
$lblSettingsGroupSaveStatus.Location = New-Object System.Drawing.Point(244, 50)
$lblSettingsGroupSaveStatus.Font = New-Object System.Drawing.Font($lblSettingsGroupSaveStatus.Font, [System.Drawing.FontStyle]::Bold)

$settingsGroupTopPanel.Controls.AddRange(@($lblSettingsGroupTarget, $cmbSettingsGroupTarget, $btnSettingsNewGroup, $lnkSettingsOpenXlsx, $btnSettingsGroupSave, $btnSettingsGroupReload, $lblSettingsGroupSaveStatus))

# Label/LinkLabelはAutoSizeによる実際のHeightが親へのAddより前だと仮の値（23）のままで、
# 親に追加された後でないと正しい値（例: 17）に確定しない。TextBox/ComboBoxも指定したHeightを
# 無視してフォントに応じた高さに強制されるため、いずれもControls.Addの後で実際のHeightを見て
# Y位置を計算しないと縦の中央が揃わない（New-CategoryTabControlの入力欄と同じ理由）
$settingsRow1CenterY = 26
$lblSettingsGroupTarget.Location = New-Object System.Drawing.Point(20, ($settingsRow1CenterY - [int]($lblSettingsGroupTarget.Height / 2)))
$cmbSettingsGroupTarget.Location = New-Object System.Drawing.Point(90, ($settingsRow1CenterY - [int]($cmbSettingsGroupTarget.Height / 2)))
$btnSettingsNewGroup.Location = New-Object System.Drawing.Point(360, ($settingsRow1CenterY - [int]($btnSettingsNewGroup.Height / 2)))
$lnkSettingsOpenXlsx.Location = New-Object System.Drawing.Point(510, ($settingsRow1CenterY - [int]($lnkSettingsOpenXlsx.Height / 2)))

$settingsGroupFieldPanel = New-Object System.Windows.Forms.Panel
$settingsGroupFieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsGroupFieldPanel.AutoScroll = $true

$tabSettingsGroup.Controls.Add($settingsGroupFieldPanel)
$tabSettingsGroup.Controls.Add($settingsGroupTopPanel)

# グループ一覧はclients\直下の*.xlsx（clients\template\は対象外）から拾う。
# 既存グループの実行対象判定（%TargetGroupNameFilter%.xlsx）と同じ考え方
function Update-SettingsGroupList {
    $selected = $cmbSettingsGroupTarget.SelectedItem
    $script:suppressComboSync = $true
    $cmbSettingsGroupTarget.Items.Clear()
    foreach ($groupName in (Get-GroupNames)) {
        $cmbSettingsGroupTarget.Items.Add($groupName) | Out-Null
    }
    if ($selected -and $cmbSettingsGroupTarget.Items.Contains($selected)) {
        $cmbSettingsGroupTarget.SelectedItem = $selected
    } elseif ($cmbSettingsGroupTarget.Items.Count -gt 0) {
        $cmbSettingsGroupTarget.SelectedIndex = 0
    }
    $script:suppressComboSync = $false
}

function Get-CommonSettingsFieldRows {
    $raw = Get-SetLineRawValues -Path (Join-Path $basePath "common-env.bat")
    foreach ($varName in $commonSettingsVars) {
        [PSCustomObject]@{ Key = $varName; VarName = $varName; Group = "BASE"; Value = $raw[$varName] }
    }
    # TargetDateCodeField/TargetUserCodeFieldは全グループ共通のためcommon-env.bat側で持つ
    $rawDaily = Get-SuffixedRawValues -RawValues $raw -Suffix $dailyReportSuffix -VarNames $commonReportVars
    $rawPulse = Get-SuffixedRawValues -RawValues $raw -Suffix $pulseSurveySuffix -VarNames $commonReportVars
    foreach ($varName in $commonReportVars) {
        [PSCustomObject]@{ Key = "DAILY_$varName"; VarName = $varName; Group = "DAILY"; Value = $rawDaily[$varName] }
    }
    foreach ($varName in $commonReportVars) {
        [PSCustomObject]@{ Key = "PULSE_$varName"; VarName = $varName; Group = "PULSE"; Value = $rawPulse[$varName] }
    }
}

function Get-GroupSettingsFieldRows {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $templateDefaults = Get-GroupTemplateDefaults
    $rawGroup = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)
    $rawDaily = Get-SuffixedRawValues -RawValues $rawGroup -Suffix $dailyReportSuffix -VarNames $groupReportVars
    $rawPulse = Get-SuffixedRawValues -RawValues $rawGroup -Suffix $pulseSurveySuffix -VarNames $groupReportVars

    foreach ($varName in $authVars) {
        $value = if ($rawGroup.ContainsKey($varName)) { $rawGroup[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "AUTH_$varName"; VarName = $varName; Group = "AUTH"; Value = $value }
    }
    foreach ($varName in $groupReportVars) {
        $value = if ($rawDaily.ContainsKey($varName)) { $rawDaily[$varName] } else { $templateDefaults.Daily[$varName] }
        [PSCustomObject]@{ Key = "DAILY_$varName"; VarName = $varName; Group = "DAILY"; Value = $value }
    }
    foreach ($varName in $groupReportVars) {
        $value = if ($rawPulse.ContainsKey($varName)) { $rawPulse[$varName] } else { $templateDefaults.Pulse[$varName] }
        [PSCustomObject]@{ Key = "PULSE_$varName"; VarName = $varName; Group = "PULSE"; Value = $value }
    }
}

$script:settingsCommonFieldTextBoxes = @{}
$script:settingsGroupFieldTextBoxes = @{}

# 共通タブ・グループ別タブ共通の描画処理。$TextBoxesへ描画結果（Key→TextBox）を書き戻す
function Render-SettingsFields {
    param(
        [System.Windows.Forms.Panel]$Panel,
        [array]$Rows,
        [hashtable]$TextBoxes
    )
    $Panel.Controls.Clear()
    $TextBoxes.Clear()

    $y = 10
    $lastGroup = ""
    foreach ($field in $Rows) {
        if ($field.Group -ne $lastGroup) {
            if ($lastGroup -ne "") {
                $y += 10
                $separator = New-Object System.Windows.Forms.Panel
                $separator.BackColor = [System.Drawing.Color]::LightGray
                $separator.Location = New-Object System.Drawing.Point(10, $y)
                $separator.Size = New-Object System.Drawing.Size(690, 2)
                $Panel.Controls.Add($separator)
                $y += 14
            }
            $lblGroup = New-Object System.Windows.Forms.Label
            $lblGroup.Text = $settingsGroupLabels[$field.Group]
            $lblGroup.AutoSize = $true
            $lblGroup.Location = New-Object System.Drawing.Point(10, $y)
            $lblGroup.Font = New-Object System.Drawing.Font($lblGroup.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold)
            $Panel.Controls.Add($lblGroup)
            $y += 28
            $lastGroup = $field.Group
        }

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = if ($settingsVarLabels.ContainsKey($field.VarName)) { $settingsVarLabels[$field.VarName] } else { $field.VarName }
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size(220, 20)
        $lbl.Location = New-Object System.Drawing.Point(20, $y)
        $settingsToolTip.SetToolTip($lbl, $field.VarName)
        $Panel.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Text = "$($field.Value)"
        $txt.Location = New-Object System.Drawing.Point(250, ($y - 2))
        $txt.Size = New-Object System.Drawing.Size(300, 22)
        $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
        if ($settingsMaskedVars -contains $field.VarName) { $txt.UseSystemPasswordChar = $true }
        $Panel.Controls.Add($txt)

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
                $startPath = Resolve-BrowseStart $targetTxt.Text
                if ($startPath -and (Test-Path -LiteralPath $startPath)) { $dlg.SelectedPath = $startPath }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $targetTxt.Text = $dlg.SelectedPath }
            })
            $Panel.Controls.Add($btnBrowse)
        }

        # 対象アプリID（グループ別タブの業務日誌/パルスサーベイのみに出現）の行に、現在の画面入力値で
        # kintone接続を試す「テスト接続」ボタンを添える
        if ($field.VarName -eq "TargetAppIds" -and ($field.Group -eq "DAILY" -or $field.Group -eq "PULSE")) {
            $btnTestConnection = New-Object System.Windows.Forms.Button
            $btnTestConnection.Text = "テスト接続"
            $btnTestConnection.Location = New-Object System.Drawing.Point(560, ($y - 3))
            $btnTestConnection.Size = New-Object System.Drawing.Size(90, 24)
            $btnTestConnection.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $btnTestConnection.Tag = $field.Group
            $btnTestConnection.Add_Click({ Test-KintoneConnection -ReportGroup $this.Tag })
            $Panel.Controls.Add($btnTestConnection)
        }

        $TextBoxes[$field.Key] = $txt
        $y += 28
    }
    return $y
}

# collect-data-defs.txt（アプリデータ集計の列定義。[セクション見出し]＋「元の列名[,新しい列名]」の
# 表形式）を、行の追加・削除ができる表形式のUIで編集する。全グループ共通の内容なので共通タブの末尾に置く。
# セクション見出しはcommon-env.bat側の*SourceType変数名（例: DailyReportSourceType）をそのまま使う。
# 実際の出力ファイル名はその変数の値（業務日誌/パルスサーベイ等）が決めるため、画面では
# 「ファイル名」欄をこの変数名の選択式（ComboBox）にして、値そのものは編集させない
$collectDataDefsPath = Join-Path $basePath "collect-data-defs.txt"
# $null=未読込（初回描画時にファイルから読み込む）。以降は編集中の内容をここに保持し、
# 行追加・削除のたびの再描画でも未保存の入力内容が消えないようにする
$script:collectDataDefsSections = $null
$script:collectDataDefsRowControls = @()

function Get-CollectDataDefsSourceTypeVarNames {
    return @($script:commonEnvVars.Keys | Where-Object { $_ -like '*SourceType' } | Sort-Object)
}

function ConvertFrom-CollectDataDefsText {
    param([string]$Text)
    $sections = [System.Collections.Generic.List[object]]::new()
    $currentKey = $null
    $currentRows = $null
    foreach ($rawLine in ($Text -split "`r`n|`n")) {
        $trimmed = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -match '^\[(.+)\]$') {
            if ($currentKey) { $sections.Add([PSCustomObject]@{ Key = $currentKey; Rows = $currentRows }) }
            $currentKey = $Matches[1]
            $currentRows = [System.Collections.Generic.List[object]]::new()
            continue
        }
        if ($null -eq $currentRows) { continue }
        $parts = $trimmed -split ',', 2
        $currentRows.Add([PSCustomObject]@{
            OrgName = $parts[0]
            NewName = if ($parts.Count -ge 2) { $parts[1] } else { "" }
        })
    }
    if ($currentKey) { $sections.Add([PSCustomObject]@{ Key = $currentKey; Rows = $currentRows }) }
    return $sections
}

function ConvertTo-CollectDataDefsText {
    param($Sections)
    $lines = @()
    foreach ($section in $Sections) {
        $lines += "[$($section.Key)]"
        foreach ($row in $section.Rows) {
            if ([string]::IsNullOrWhiteSpace($row.OrgName)) { continue }
            $lines += if ([string]::IsNullOrWhiteSpace($row.NewName)) { $row.OrgName } else { "$($row.OrgName),$($row.NewName)" }
        }
        $lines += ""
    }
    return ($lines -join "`r`n")
}

# 描画済みのテキストボックスの現在値を$script:collectDataDefsSectionsへ書き戻す。
# 再描画（行追加・削除）の直前に必ず呼び、それまでの入力内容を失わないようにする
function Sync-CollectDataDefsFromControls {
    foreach ($entry in $script:collectDataDefsRowControls) {
        $entry.Row.OrgName = $entry.OrgBox.Text
        $entry.Row.NewName = $entry.NewBox.Text
    }
}

function Add-CollectDataDefsEditor {
    param([int]$StartY)

    if ($null -eq $script:collectDataDefsSections) {
        $text = if (Test-Path -LiteralPath $collectDataDefsPath) {
            [System.IO.File]::ReadAllText($collectDataDefsPath, (New-Object System.Text.UTF8Encoding($false)))
        } else {
            ""
        }
        $script:collectDataDefsSections = ConvertFrom-CollectDataDefsText -Text $text
    }
    $script:collectDataDefsRowControls = @()

    $y = $StartY + 10
    $separator = New-Object System.Windows.Forms.Panel
    $separator.BackColor = [System.Drawing.Color]::LightGray
    $separator.Location = New-Object System.Drawing.Point(10, $y)
    $separator.Size = New-Object System.Drawing.Size(690, 2)
    $settingsCommonFieldPanel.Controls.Add($separator)
    $y += 14

    $lblDefs = New-Object System.Windows.Forms.Label
    $lblDefs.Text = "アプリデータ集計の列定義"
    $lblDefs.AutoSize = $true
    $lblDefs.Location = New-Object System.Drawing.Point(10, $y)
    $lblDefs.Font = New-Object System.Drawing.Font($lblDefs.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold)
    $settingsCommonFieldPanel.Controls.Add($lblDefs)
    $y += 30

    $sourceTypeVarNames = Get-CollectDataDefsSourceTypeVarNames

    foreach ($section in $script:collectDataDefsSections) {
        $lblFileNameCaption = New-Object System.Windows.Forms.Label
        $lblFileNameCaption.Text = "ファイル名"
        $lblFileNameCaption.AutoSize = $false
        $lblFileNameCaption.Size = New-Object System.Drawing.Size(220, 20)
        $lblFileNameCaption.Location = New-Object System.Drawing.Point(20, $y)
        $lblFileNameCaption.Font = New-Object System.Drawing.Font($lblFileNameCaption.Font.FontFamily, 9, [System.Drawing.FontStyle]::Bold)
        $settingsCommonFieldPanel.Controls.Add($lblFileNameCaption)
        $y += 22

        $cmbFileName = New-Object System.Windows.Forms.ComboBox
        $cmbFileName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cmbFileName.Location = New-Object System.Drawing.Point(20, $y)
        $cmbFileName.Size = New-Object System.Drawing.Size(300, 24)
        foreach ($varName in $sourceTypeVarNames) {
            $displayText = if ($script:commonEnvVars.ContainsKey($varName)) { $script:commonEnvVars[$varName] } else { $varName }
            $cmbFileName.Items.Add([PSCustomObject]@{ VarName = $varName; DisplayText = $displayText }) | Out-Null
        }
        $cmbFileName.DisplayMember = "DisplayText"
        $matchedItem = $cmbFileName.Items | Where-Object { $_.VarName -eq $section.Key } | Select-Object -First 1
        if ($matchedItem) {
            $cmbFileName.SelectedItem = $matchedItem
        } elseif ($cmbFileName.Items.Count -gt 0) {
            $cmbFileName.SelectedIndex = 0
        }
        $cmbFileName.Tag = $section
        $cmbFileName.Add_SelectedIndexChanged({
            Sync-CollectDataDefsFromControls
            $this.Tag.Key = $this.SelectedItem.VarName
        })
        $settingsCommonFieldPanel.Controls.Add($cmbFileName)
        $y += 30

        $lblOrgHeader = New-Object System.Windows.Forms.Label
        $lblOrgHeader.Text = "変更前"
        $lblOrgHeader.AutoSize = $false
        $lblOrgHeader.Size = New-Object System.Drawing.Size(210, 18)
        $lblOrgHeader.Location = New-Object System.Drawing.Point(20, $y)
        $settingsCommonFieldPanel.Controls.Add($lblOrgHeader)

        $lblNewHeader = New-Object System.Windows.Forms.Label
        $lblNewHeader.Text = "変更後"
        $lblNewHeader.AutoSize = $false
        $lblNewHeader.Size = New-Object System.Drawing.Size(210, 18)
        $lblNewHeader.Location = New-Object System.Drawing.Point(240, $y)
        $settingsCommonFieldPanel.Controls.Add($lblNewHeader)
        $y += 20

        foreach ($row in @($section.Rows)) {
            $txtOrg = New-Object System.Windows.Forms.TextBox
            $txtOrg.Text = "$($row.OrgName)"
            $txtOrg.Location = New-Object System.Drawing.Point(20, $y)
            $txtOrg.Size = New-Object System.Drawing.Size(210, 22)
            $settingsCommonFieldPanel.Controls.Add($txtOrg)

            $txtNew = New-Object System.Windows.Forms.TextBox
            $txtNew.Text = "$($row.NewName)"
            $txtNew.Location = New-Object System.Drawing.Point(240, $y)
            $txtNew.Size = New-Object System.Drawing.Size(210, 22)
            $settingsCommonFieldPanel.Controls.Add($txtNew)

            $btnDeleteRow = New-Object System.Windows.Forms.Button
            $btnDeleteRow.Text = "削除"
            $btnDeleteRow.Location = New-Object System.Drawing.Point(460, ($y - 1))
            $btnDeleteRow.Size = New-Object System.Drawing.Size(60, 24)
            $btnDeleteRow.Tag = [PSCustomObject]@{ Section = $section; Row = $row }
            $btnDeleteRow.Add_Click({
                Sync-CollectDataDefsFromControls
                $ctx = $this.Tag
                $ctx.Section.Rows.Remove($ctx.Row) | Out-Null
                Update-CommonSettingsFields
            })
            $settingsCommonFieldPanel.Controls.Add($btnDeleteRow)

            $script:collectDataDefsRowControls += [PSCustomObject]@{ Section = $section; Row = $row; OrgBox = $txtOrg; NewBox = $txtNew }
            $y += 26
        }

        $btnAddRow = New-Object System.Windows.Forms.Button
        $btnAddRow.Text = "＋ 行を追加"
        $btnAddRow.Location = New-Object System.Drawing.Point(20, $y)
        $btnAddRow.Size = New-Object System.Drawing.Size(100, 24)
        $btnAddRow.Tag = $section
        $btnAddRow.Add_Click({
            Sync-CollectDataDefsFromControls
            $this.Tag.Rows.Add([PSCustomObject]@{ OrgName = ""; NewName = "" })
            Update-CommonSettingsFields
        })
        $settingsCommonFieldPanel.Controls.Add($btnAddRow)
        $y += 36
    }
}

function Save-CollectDataDefs {
    Sync-CollectDataDefsFromControls
    $text = ConvertTo-CollectDataDefsText -Sections $script:collectDataDefsSections
    [System.IO.File]::WriteAllText($collectDataDefsPath, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Update-CommonSettingsFields {
    $scrollX = -$settingsCommonFieldPanel.AutoScrollPosition.X
    $scrollY = -$settingsCommonFieldPanel.AutoScrollPosition.Y

    $endY = Render-SettingsFields -Panel $settingsCommonFieldPanel -Rows (Get-CommonSettingsFieldRows) -TextBoxes $script:settingsCommonFieldTextBoxes
    Add-CollectDataDefsEditor -StartY $endY

    $settingsCommonFieldPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

function Update-GroupSettingsFields {
    $target = $cmbSettingsGroupTarget.SelectedItem
    Render-SettingsFields -Panel $settingsGroupFieldPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target) -TextBoxes $script:settingsGroupFieldTextBoxes | Out-Null
}

function Get-CommonSettingsFieldValue {
    param([string]$Key)
    return $script:settingsCommonFieldTextBoxes[$Key].Text
}

function Get-GroupSettingsFieldValue {
    param([string]$Key)
    return $script:settingsGroupFieldTextBoxes[$Key].Text
}

# 業務日誌/パルスサーベイの各セクションの「テスト接続」ボタン用。画面上の（未保存の）入力値を使って
# kintoneのフィールド取得APIを呼び、認証情報・対象アプリIDの組み合わせが有効かその場で確認する。
# TargetAppIdsはcreate-app-data.ps1のGet-FieldCodeListと同じくカンマ・空白区切りで複数指定できるため、
# 1つずつ個別に呼び分けて成功/失敗をID単位で表示する
function Test-KintoneConnection {
    param([string]$ReportGroup)

    $kintoneSubdomain = Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain"
    $kintoneId = Get-GroupSettingsFieldValue "AUTH_KintoneID"
    $kintonePw = Get-GroupSettingsFieldValue "AUTH_KintonePW"
    $targetAppIdsValue = Get-GroupSettingsFieldValue "${ReportGroup}_TargetAppIds"
    $targetAppIds = @($targetAppIdsValue -split '[,\s]+' | Where-Object { $_ })

    if ($targetAppIds.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("対象アプリIDが未入力です。", "テスト接続", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $baseUrl = "https://$kintoneSubdomain.cybozu.com"
    $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${kintoneId}:${kintonePw}"))

    # IDが複数になっても横に長くならないよう、1件1行の縦並びで表示する
    $resultLines = @()
    $hasFailure = $false
    foreach ($targetAppId in $targetAppIds) {
        try {
            $fieldData = Get-CurrentAppFieldData -TargetAppId $targetAppId -BaseUrl $baseUrl -Authorization $authorization
            $fieldCount = @($fieldData.PSObject.Properties).Count
            $resultLines += "[成功] $targetAppId（フィールド数: $fieldCount）"
        } catch {
            $hasFailure = $true
            $resultLines += "[失敗] $targetAppId： $($_.Exception.Message)"
        }
    }

    $icon = if ($hasFailure) { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
    [System.Windows.Forms.MessageBox]::Show(($resultLines -join "`r`n"), "テスト接続", [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
}

function Save-CommonSettings {
    $path = Join-Path $basePath "common-env.bat"

    # TargetDateCodeField_Daily等サフィックス付きの実際の行名→画面の入力欄キー（DAILY_xxx/PULSE_xxx）の対応表
    $reportVarKeyMap = @{}
    foreach ($varName in $commonReportVars) {
        $reportVarKeyMap["$varName$dailyReportSuffix"] = "DAILY_$varName"
        $reportVarKeyMap["$varName$pulseSurveySuffix"] = "PULSE_$varName"
    }

    $newLines = foreach ($line in [System.IO.File]::ReadAllLines($path, $script:cp932Encoding)) {
        $m = $settingsLineRegex.Match($line.Trim())
        if ($m.Success -and ($commonSettingsVars -contains $m.Groups["var"].Value)) {
            $varName = $m.Groups["var"].Value
            $val = Get-CommonSettingsFieldValue $varName
            "set `"$varName=$val`""
        } elseif ($m.Success -and $reportVarKeyMap.ContainsKey($m.Groups["var"].Value)) {
            $rawVarName = $m.Groups["var"].Value
            $val = Get-CommonSettingsFieldValue $reportVarKeyMap[$rawVarName]
            "set `"$rawVarName=$val`""
        } else {
            $line
        }
    }
    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($path, $content, $script:cp932Encoding)
}

function Save-GroupSettings {
    param([string]$GroupName)

    # Authorizationは画面上の編集項目からは外したが、実行スクリプト側は今も参照するため、
    # 上書き前の既存の値をそのまま引き継ぐ（新規グループはclients\template\の既定値＝空欄になる）
    $existingAuth = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)
    $authorizationValue = if ($existingAuth.ContainsKey("Authorization")) { $existingAuth["Authorization"] } else { (Get-GroupTemplateDefaults).Auth["Authorization"] }

    $groupLines = @("@echo off", "")
    foreach ($varName in $authVars) {
        $val = Get-GroupSettingsFieldValue "AUTH_$varName"
        $groupLines += "set `"$varName=$val`""
    }
    $groupLines += "set `"Authorization=$authorizationValue`""
    # BaseUrlは画面では編集させず、KintoneSubdomainから常に導出する
    $groupLines += "set `"BaseUrl=https://%KintoneSubdomain%.cybozu.com`""
    $groupLines += ""
    foreach ($varName in $groupReportVars) {
        $val = Get-GroupSettingsFieldValue "DAILY_$varName"
        $groupLines += "set `"$varName$dailyReportSuffix=$val`""
    }
    $groupLines += ""
    foreach ($varName in $groupReportVars) {
        $val = Get-GroupSettingsFieldValue "PULSE_$varName"
        $groupLines += "set `"$varName$pulseSurveySuffix=$val`""
    }
    $groupLines += ""
    [System.IO.File]::WriteAllText((Get-GroupBatPath $GroupName), (($groupLines -join "`r`n") + "`r`n"), $script:cp932Encoding)

    # 受講生データ（xlsx）は既存グループでは上書きしない。新規グループのときだけclients\template\からコピーする
    $xlsxPath = Get-GroupXlsxPath $GroupName
    if (!(Test-Path -LiteralPath $xlsxPath)) {
        $templateXlsxPath = Join-Path $clientsTemplateDir "client.xlsx"
        if (Test-Path -LiteralPath $templateXlsxPath) {
            Copy-Item -LiteralPath $templateXlsxPath -Destination $xlsxPath
        }
    }
}

# 一括実行タブ・各カテゴリタブの「対象グループ」ドロップダウンは起動時に作った$groupOptionsを
# 元にしているため、設定タブでグループを新規作成・保存しても自動では反映されない。
# 選択中の値はできるだけ保つ（見つからなければ「すべて」に戻す）
function Update-GroupComboBoxItems {
    param([System.Windows.Forms.ComboBox]$ComboBox, [array]$Options)
    if (-not $ComboBox) { return }
    $selectedValue = if ($ComboBox.SelectedItem) { "$($ComboBox.SelectedItem.Value)" } else { "" }
    $ComboBox.Items.Clear()
    foreach ($opt in $Options) { $ComboBox.Items.Add($opt) | Out-Null }
    $matchedOption = $Options | Where-Object { "$($_.Value)" -eq $selectedValue } | Select-Object -First 1
    if ($matchedOption) {
        $ComboBox.SelectedItem = $matchedOption
    } elseif ($ComboBox.Items.Count -gt 0) {
        $ComboBox.SelectedIndex = 0
    }
}

function Update-GroupDropdowns {
    $script:groupOptions = @([PSCustomObject]@{ Text = "すべて"; Value = "" })
    foreach ($groupName in (Get-GroupNames)) {
        $script:groupOptions += [PSCustomObject]@{ Text = $groupName; Value = $groupName }
    }

    Update-GroupComboBoxItems -ComboBox $cmbBatchGroup -Options $script:groupOptions
    foreach ($cd in $categoryDefs) {
        foreach ($bd in $cd.ButtonDefs) {
            if ($bd.InputControls -and $bd.InputControls.ContainsKey("TargetGroupNameFilter")) {
                Update-GroupComboBoxItems -ComboBox $bd.InputControls["TargetGroupNameFilter"] -Options $script:groupOptions
            }
        }
    }
}

$btnSettingsCommonSave.Add_Click({
    Save-CommonSettings
    Save-CollectDataDefs
    Update-CommonSettingsFields
    $lblSettingsCommonSaveStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblSettingsCommonSaveStatus.Text = "保存しました"
})

$btnSettingsCommonReload.Add_Click({
    # 未保存の編集内容を破棄してcollect-data-defs.txtをディスクから読み直す
    $script:collectDataDefsSections = $null
    Update-CommonSettingsFields
    $lblSettingsCommonSaveStatus.ForeColor = [System.Drawing.Color]::Black
    $lblSettingsCommonSaveStatus.Text = "再読込しました"
})

$btnSettingsGroupSave.Add_Click({
    $target = $cmbSettingsGroupTarget.SelectedItem
    if (!$target) { return }
    Save-GroupSettings -GroupName $target
    Update-SettingsGroupList
    Update-GroupSettingsFields
    Update-GroupDropdowns
    $lblSettingsGroupSaveStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblSettingsGroupSaveStatus.Text = "保存しました"
})

$btnSettingsGroupReload.Add_Click({
    Update-GroupSettingsFields
    $lblSettingsGroupSaveStatus.ForeColor = [System.Drawing.Color]::Black
    $lblSettingsGroupSaveStatus.Text = "再読込しました"
})

$btnSettingsNewGroup.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("グループ名を入力してください", "グループの新規作成", "")
    $newName = $newName.Trim()
    if (!$newName) { return }

    if ($cmbSettingsGroupTarget.Items.Contains($newName) -or (Test-Path -LiteralPath (Get-GroupXlsxPath $newName)) -or (Test-Path -LiteralPath (Get-GroupBatPath $newName))) {
        [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "グループの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $cmbSettingsGroupTarget.Items.Add($newName) | Out-Null
    $cmbSettingsGroupTarget.SelectedItem = $newName
})

$lnkSettingsOpenXlsx.Add_LinkClicked({
    $target = $cmbSettingsGroupTarget.SelectedItem
    if (!$target) {
        [System.Windows.Forms.MessageBox]::Show("対象グループが選択されていません。", "受講生データを開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    Open-FolderOrWarn -Path (Get-GroupXlsxPath $target)
})

$cmbSettingsGroupTarget.Add_SelectedIndexChanged({
    if (!$script:suppressComboSync) { Update-GroupSettingsFields }
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
Update-CommonSettingsFields
Update-GroupSettingsFields

# ps2exeビルド環境ではタブの既定選択がずれることがあるため明示的に指定する
$tabControl.SelectedTab = $tabBatchAll

[System.Windows.Forms.Application]::Run($form)
