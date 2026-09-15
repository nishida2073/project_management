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

# 子プロセス（Invoke-BatProcess経由で起動するbat/ps1）のWrite-Messageに、
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
            [PSCustomObject]@{ Label = "業務日誌"; BatchLabel = "アプリデータ作成-業務日誌"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "create-daily-report.bat"); OpenTarget = $script:commonEnvVars["OutputReportDir"]; Inputs = $dateAndGroupInputs }
            [PSCustomObject]@{ Label = "パルスサーベイ"; BatchLabel = "アプリデータ作成-パルスサーベイ"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "create-pulse-survey.bat"); OpenTarget = $script:commonEnvVars["OutputReportDir"]; Inputs = $dateAndGroupInputs }
        )
    }
    [PSCustomObject]@{
        Label = "アプリデータ集計"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌・パルスサーベイ"; BatchLabel = "アプリデータ集計-業務日誌・パルスサーベイ"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-app-data.bat"); OpenTarget = $script:commonEnvVars["OutputCollectDataRootDir"]; Inputs = $dateAndGroupInputs }
        )
    }
    [PSCustomObject]@{
        Label = "アラート集計"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌・パルスサーベイ"; BatchLabel = "アラート集計-業務日誌・パルスサーベイ"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "check-alert.bat"); OpenTarget = $script:commonEnvVars["OutputAlertRootDir"]; Inputs = $dateAndGroupInputs }
            [PSCustomObject]@{ Label = "投稿"; BatchLabel = "アラート集計-投稿"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "post-alert-result.bat"); OpenTarget = { param($groupName) Get-GroupKintoneThreadUrl -GroupName $groupName }; Inputs = $dateAndGroupInputs }
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
# 外側タブ（実行／ログ／設定。package-generator/kintone-resourse-generatorと同じ構成）。
# ps2exeでビルドした実行ファイルではTabPageCollection.Insert()がNotSupportedExceptionになるため、
# 後から並び替えるのではなく、最初から最終的な順序でAddしていく必要がある
# =========================================

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill

$tabRun = New-Object System.Windows.Forms.TabPage
$tabRun.Text = "実行"
$tabControl.Controls.Add($tabRun)

$form.Controls.Add($tabControl)

# =========================================
# 一括実行タブ（package-generatorの実行タブUIを参考にしたレイアウト：
# チェックボックスで対象ステップを選び、共通入力欄を使って1つの実行ボタンで一括実行する）
#
# 「実行」タブの中を一括実行タブ＋カテゴリごとのタブに分けるため、TabControlをここで作って
# このタブを最初にAddし、後段の「実行タブ（カテゴリごと）」ではこのTabControlに追記してもらう形にする。
# 同じくps2exeのInsert()制限のため、最初から最終的な順序でAddしていく必要がある
# =========================================

$execTabControl = New-Object System.Windows.Forms.TabControl

# IncludeInBatchを$falseにしたButtonDefだけ、一括実行タブの対象から外せる（実行タブ側には影響しない）
$allButtonDefs = @()
foreach ($cd in $categoryDefs) {
    foreach ($bd in $cd.ButtonDefs) {
        if ($bd.IncludeInBatch -ne $false) { $allButtonDefs += $bd }
    }
}

$tabBatchAll = New-Object System.Windows.Forms.TabPage
$tabBatchAll.Text = "一括実行"
$execTabControl.Controls.Add($tabBatchAll)

$batchTab = New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allButtonDefs `
    -Inputs @(
        [PSCustomObject]@{ Name = "TargetDate"; Label = "対象日"; Default = $defaultTargetDate; LabelWidth = 60; InputWidth = 90 }
        [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象グループ"; Options = $groupOptions; LabelWidth = 90; InputWidth = 120 }
    ) `
    -OnOpenClick {
        param($bd, $inputControls)
        $target = $bd.OpenTarget
        if ($target -is [scriptblock]) {
            $groupValue = Get-InputValue -Control $inputControls["TargetGroupNameFilter"]
            $target = & $target $groupValue
        }
        Open-TargetOrWarn -Path $target
    }

$batchPanel = $batchTab.Panel
$script:batchInputControls = $batchTab.InputControls
$script:batchStepCheckboxes = $batchTab.CheckBoxes
$btnRunAll = $batchTab.RunButton
$lblBatchStatus = $batchTab.StatusLabel
$script:batchRunButtons = @($btnRunAll)

function Start-BatchRunAll {
    Invoke-BatchRunAll -ButtonDefs $allButtonDefs -CheckBoxes $script:batchStepCheckboxes `
        -StatusLabel $lblBatchStatus -ExtraControls @($script:batchInputControls.Values) `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $basePath -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs {
                    param($bd)
                    $batArgs = @()
                    foreach ($inputDef in $bd.Inputs) {
                        $batArgs += Get-InputValue -Control $script:batchInputControls[$inputDef.Name]
                    }
                    return $batArgs
                }
        }
}

$btnRunAll.Add_Click({ Start-BatchRunAll })

# =========================================
# 実行タブ（カテゴリごとに分割）
# =========================================

$tabResult = New-CategoryTabControl -TabControl $execTabControl -CategoryDefs $categoryDefs -OnRunClick {
    param($bd)
    Invoke-BatButton -ButtonDef $bd -WorkingDirectory $basePath -Form $form `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -CurrentProcessRef ([ref]$script:currentProc) `
        -GetBatArgs {
            param($bd)
            $batArgs = @()
            $inputMap = $bd.InputControls
            if ($inputMap) {
                foreach ($inputDef in $bd.Inputs) {
                    $batArgs += Get-InputValue -Control $inputMap[$inputDef.Name]
                }
            }
            return $batArgs
        }
}
$script:runButtons = $tabResult.RunButtons

# 一括実行タブが既定の選択タブになるため、New-CategoryTabControl側で計算済みだった
# 初期の$execTabControl.Height（アプリデータ作成タブ基準）をこのタブの内容量に合わせて上書きする。
# 45はNew-CategoryTabControlの$TabHeaderAllowance既定値
$execTabControl.Height = 45 + $batchPanel.Height

# =========================================
# ログ（「実行」タブの中で常に表示。ログ／設定タブへ切り替えると見えなくなる）
# =========================================

$logSpacer = New-Object System.Windows.Forms.Panel
$logSpacer.Height = 10
$logSpacer.Dock = [System.Windows.Forms.DockStyle]::Top

$txtLog = New-LogTextBox

# 視覚的な上→下の並び: execTabControl → logSpacer → txtLog（Dock=Fillで残り全域を埋める）
Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($execTabControl, $logSpacer, $txtLog)

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    Set-ButtonsEnabled -Buttons $script:runButtons -Enabled $Enabled
    Set-ButtonsEnabled -Buttons $script:batchRunButtons -Enabled $Enabled
}

# =========================================
# ログタブ（package-generator/kintone-resourse-generatorの「ログ」タブを参考にしたレイアウト：
# 対象グループ・工程で絞り込んで過去ログを閲覧する）。
# 実行中ログ（txtLog）は「実行」タブの中にしかないため、このタブに来ると自動的に見えなくなる。
# このタブ自身はDock=Top/Fillの組み合わせを直下に置くだけでよい
# =========================================

$tabLogs = New-Object System.Windows.Forms.TabPage
$tabLogs.Text = "ログ"
$tabControl.Controls.Add($tabLogs)

# ログの閲覧対象は一括実行の対象外（IncludeInBatch=$false）も含めた全ButtonDef
$allButtonDefsForLog = @($categoryDefs | ForEach-Object { $_.ButtonDefs })

$script:logTab = New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefsForLog `
    -LabelFn { param($bd) Get-BatchDisplayLabel -ButtonDef $bd } `
    -ExtraLabelText "対象グループ" -ExtraComboWidth 150 `
    -GetLogPathFn { $script:commonEnvVars["LOG_DIR"] } `
    -OnUpdateLogView { Update-LogView }
$cmbLogGroup = $script:logTab.ExtraCombo
$cmbLogGroup.DisplayMember = "Text"
foreach ($opt in $groupOptions) { $cmbLogGroup.Items.Add($opt) | Out-Null }
if ($cmbLogGroup.Items.Count -gt 0) { $cmbLogGroup.SelectedIndex = 0 }

# 各.ps1はNew-WorkerLogPathで「<バッチ名>-<対象グループ>-<対象日等>_<timestamp>.log」という
# ファイル名で書き出す（bats\library\common.ps1参照）。<バッチ名>はButtonDef.BatchPathの
# ファイル名（拡張子無し）と一致するため、それをそのままフィルタの接頭辞に使う
foreach ($radio in $script:logTab.Radios) {
    $radio.Add_CheckedChanged({ if ($this.Checked) { Update-LogView } })
}
$cmbLogGroup.Add_SelectedIndexChanged({ Update-LogView })

Update-LogView

# =========================================
# 設定タブ（package-generatorの設定タブUIを参考にしたレイアウト：
# 「共通」「グループ別」のサブタブに分けて編集する）
#
# 「共通」タブはcommon-env.bat（対象日・対象グループに関わらず共通のパス設定に加え、
# 全グループ共通の業務日誌/パルスサーベイのフィールドコード）を直接編集する。
# 「グループ別」タブはグループを選ぶと、そのグループのclients\<グループ名>.bat（認証情報＋
# 業務日誌/パルスサーベイの対象アプリID。種別ごとにcommon-env.bat側のSourceType_<接尾辞>
# から検出した接尾辞を付けた変数名で1ファイルにまとめて持つ）を編集する。
# 新規グループはclients\template\の内容を初期値として使う（保存するまでファイルは作成しない）
# =========================================

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "設定"
$tabControl.Controls.Add($tabSettings)

$clientsTemplateDir = Join-Path $clientsDir "template"

function Get-GroupXlsxPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.xlsx" }

# 設定タブの各フィールドの生の値には、common-env.bat内の%BASE_PATH%や%OutputRootDir%のような
# %VAR%トークンがそのまま残っている（%~dp0のようなバッチ専用トークンは.NET側では解決できないため、
# common-env.bat側は%BASE_PATH%を使う方式に統一済み）。$script:commonEnvVars（起動時に
# common-env.batを実際に実行して解決済みの値）を使って再帰的に展開する
$script:commonEnvResolver = { param($name) $script:commonEnvVars[$name] }

$commonSettingsVars = @("ClientDataRootDir", "OutputRootDir", "TemplateRootDir", "LOG_DIR", "OutputReportDir", "OutputCollectDataRootDir", "OutputAlertRootDir", "OutputAlertBackupDir")
$authVars = @("KintoneSubdomain", "KintoneLoginName", "KintonePassword")
$postVars = @("SpaceId", "ThreadId", "MentionUserCodes", "CommentTextTemplate")

$groupReportVars = @("TargetAppIds")
$commonReportVars = @("TargetDateCodeField", "TargetUserCodeField")

# 業務日誌/パルスサーベイのような「種別」の一覧をcommon-env.batから動的に検出する。
# common-env.batに"SourceType_<接尾辞>"（例: SourceType_Daily=業務日誌）を追加するだけで、
# 設定タブに新しい種別のセクションが増えるようにするための仕組み。変数名の"_<接尾辞>"部分が
# そのままTargetAppIds_<接尾辞>等の変数名サフィックスになる（別にSuffix変数を持つ必要はない）。
# 新しいcreate-xxx.batを作る場合も、設定タブ側のコード変更は不要
function Get-ReportTypeDefs {
    $types = @()
    foreach ($key in $script:commonEnvVars.Keys) {
        if ($key -notmatch '^SourceType(_.+)$') { continue }
        $suffix = $Matches[1]
        $types += [PSCustomObject]@{
            Prefix = $suffix.TrimStart('_')
            Suffix = $suffix
            Label  = $script:commonEnvVars[$key]
        }
    }
    return @($types | Sort-Object Prefix)
}

$settingsGroupLabels = @{ "BASE" = "基本設定"; "AUTH" = "認証情報"; "POST" = "投稿先" }
foreach ($rt in (Get-ReportTypeDefs)) { $settingsGroupLabels[$rt.Prefix] = $rt.Label }
$settingsVarLabels = @{
    "ClientDataRootDir"        = "グループデータのフォルダ"
    "OutputRootDir"            = "出力のルートフォルダ"
    "TemplateRootDir"          = "テンプレートのフォルダ"
    "LOG_DIR"                  = "ログの出力先"
    "OutputReportDir"          = "業務日誌・パルスサーベイの出力先"
    "OutputCollectDataRootDir" = "アプリデータ集計の出力先"
    "OutputAlertRootDir"       = "アラート検知結果の出力先"
    "OutputAlertBackupDir"     = "アラート検知結果のバックアップ先"
    "KintoneLoginName"         = "ログイン名"
    "KintonePassword"          = "パスワード"
    "KintoneSubdomain"         = "サブドメイン"
    "SpaceId"                  = "投稿先スペースID"
    "ThreadId"                 = "投稿先スレッドID"
    "MentionUserCodes"         = "メンション対象"
    "CommentTextTemplate"      = "投稿コメント文言"
    "TargetAppIds"             = "対象アプリID"
    "TargetDateCodeField"      = "日付フィールドコード"
    "TargetUserCodeField"      = "受講生IDフィールドコード"
}
$settingsFolderBrowseVars = @("ClientDataRootDir", "OutputRootDir", "TemplateRootDir", "LOG_DIR", "OutputReportDir", "OutputCollectDataRootDir", "OutputAlertRootDir", "OutputAlertBackupDir")
$settingsMaskedVars = @("KintonePassword")
# client.batは1変数1行(set "Var=Value")の形式で改行を持てないため、複数行入力欄は
# 保存時に実際の改行を"\n"リテラルへ変換して1行に収め、画面表示時・check-alert.ps1側の利用時に戻す
$settingsMultilineVars = @("CommentTextTemplate")
# このフィールドの次の行にテスト用ボタンを置く。グループ別タブにのみ出現するフィールドを指定すること
$settingsTrailingButtonVars = @{
    "TargetAppIds"        = { param($Panel, $Y, $Field) Add-TestActionButton -Panel $Panel -Y $Y -Text "テスト接続" -OnClick { Test-KintoneConnection -ReportGroup $Field.Group }.GetNewClosure() }
    "CommentTextTemplate" = { param($Panel, $Y, $Field) Add-TestActionButton -Panel $Panel -Y $Y -Text "テスト投稿" -OnClick { Test-KintonePostSettings } }
}

# TargetAppIds等は種別（業務日誌/パルスサーベイ等）ごとに同じ変数名を別の値で使うため、変数名に
# 各種別のSuffix（Get-ReportTypeDefs参照）を付けて区別して持つ。この関数はそのサフィックス付きの
# 生値を、サフィックスを外した変数名（$VarNamesと同じキー）のハッシュテーブルへ変換する
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
# 共通設定なのでここには含めない。ByTypeは種別のPrefix（例: Daily）をキーにした辞書
$script:groupTemplateDefaults = $null
function Get-GroupTemplateDefaults {
    if ($null -eq $script:groupTemplateDefaults) {
        $rawTemplate = Get-SetLineRawValues -Path (Join-Path $clientsTemplateDir "client.bat")
        $byType = @{}
        foreach ($rt in (Get-ReportTypeDefs)) {
            $byType[$rt.Prefix] = Get-SuffixedRawValues -RawValues $rawTemplate -Suffix $rt.Suffix -VarNames $groupReportVars
        }
        $script:groupTemplateDefaults = [PSCustomObject]@{
            Auth   = $rawTemplate
            ByType = $byType
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
$lblSettingsGroupTarget.Text = "対象グループ"
$lblSettingsGroupTarget.AutoSize = $true

$cmbSettingsGroupTarget = New-Object System.Windows.Forms.ComboBox
$cmbSettingsGroupTarget.Size = New-Object System.Drawing.Size(260, 24)
$cmbSettingsGroupTarget.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$btnSettingsGroupNewGroup = New-Object System.Windows.Forms.Button
$btnSettingsGroupNewGroup.Text = "新規作成"
$btnSettingsGroupNewGroup.Size = New-Object System.Drawing.Size(140, 24)

$lnkSettingsGroupOpenXlsx = New-Object System.Windows.Forms.LinkLabel
$lnkSettingsGroupOpenXlsx.Text = "開く"
$lnkSettingsGroupOpenXlsx.AutoSize = $true

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

$settingsGroupTopPanel.Controls.AddRange(@($lblSettingsGroupTarget, $cmbSettingsGroupTarget, $btnSettingsGroupNewGroup, $lnkSettingsGroupOpenXlsx, $btnSettingsGroupSave, $btnSettingsGroupReload, $lblSettingsGroupSaveStatus))

# Label/LinkLabelはAutoSizeによる実際のHeightが親へのAddより前だと仮の値（23）のままで、
# 親に追加された後でないと正しい値（例: 17）に確定しない。TextBox/ComboBoxも指定したHeightを
# 無視してフォントに応じた高さに強制されるため、いずれもControls.Addの後で実際のHeightを見て
# Y位置を計算しないと縦の中央が揃わない（New-CategoryTabControlの入力欄と同じ理由）
$settingsRow1CenterY = 26
$lblSettingsGroupTarget.Location = New-Object System.Drawing.Point(20, ($settingsRow1CenterY - [int]($lblSettingsGroupTarget.Height / 2)))
# ラベル幅（AutoSize）に応じて後続コントロールを詰めて配置し、ラベルの文言を変えても重ならないようにする
$cmbSettingsGroupTarget.Location = New-Object System.Drawing.Point(($lblSettingsGroupTarget.Right + 10), ($settingsRow1CenterY - [int]($cmbSettingsGroupTarget.Height / 2)))
$btnSettingsGroupNewGroup.Location = New-Object System.Drawing.Point(($cmbSettingsGroupTarget.Right + 10), ($settingsRow1CenterY - [int]($btnSettingsGroupNewGroup.Height / 2)))
$lnkSettingsGroupOpenXlsx.Location = New-Object System.Drawing.Point(($btnSettingsGroupNewGroup.Right + 10), ($settingsRow1CenterY - [int]($lnkSettingsGroupOpenXlsx.Height / 2)))

$settingsGroupFieldPanel = New-Object System.Windows.Forms.Panel
$settingsGroupFieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsGroupFieldPanel.AutoScroll = $true

$tabSettingsGroup.Controls.Add($settingsGroupFieldPanel)
$tabSettingsGroup.Controls.Add($settingsGroupTopPanel)

function Get-CommonSettingsFieldRows {
    $raw = Get-SetLineRawValues -Path (Join-Path $basePath "common-env.bat")
    foreach ($varName in $commonSettingsVars) {
        [PSCustomObject]@{ Key = $varName; VarName = $varName; Group = "BASE"; Value = $raw[$varName] }
    }
    # TargetDateCodeField/TargetUserCodeFieldは全グループ共通のためcommon-env.bat側で持つ。
    # 種別（Get-ReportTypeDefsで検出）ごとにセクションを作る
    foreach ($rt in (Get-ReportTypeDefs)) {
        $rawForType = Get-SuffixedRawValues -RawValues $raw -Suffix $rt.Suffix -VarNames $commonReportVars
        foreach ($varName in $commonReportVars) {
            [PSCustomObject]@{ Key = "$($rt.Prefix)_$varName"; VarName = $varName; Group = $rt.Prefix; Value = $rawForType[$varName] }
        }
    }
}

function Get-GroupSettingsFieldRows {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $templateDefaults = Get-GroupTemplateDefaults
    $rawGroup = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)

    foreach ($varName in $authVars) {
        $value = if ($rawGroup.ContainsKey($varName)) { $rawGroup[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "AUTH_$varName"; VarName = $varName; Group = "AUTH"; Value = $value }
    }
    foreach ($varName in $postVars) {
        $value = if ($rawGroup.ContainsKey($varName)) { $rawGroup[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "POST_$varName"; VarName = $varName; Group = "POST"; Value = $value }
    }
    foreach ($rt in (Get-ReportTypeDefs)) {
        $rawForType = Get-SuffixedRawValues -RawValues $rawGroup -Suffix $rt.Suffix -VarNames $groupReportVars
        $defaultsForType = $templateDefaults.ByType[$rt.Prefix]
        foreach ($varName in $groupReportVars) {
            $value = if ($rawForType.ContainsKey($varName)) { $rawForType[$varName] } else { $defaultsForType[$varName] }
            [PSCustomObject]@{ Key = "$($rt.Prefix)_$varName"; VarName = $varName; Group = $rt.Prefix; Value = $value }
        }
    }
}

$script:settingsCommonFieldTextBoxes = @{}
$script:settingsGroupFieldTextBoxes = @{}

# メンション設定（MentionUserCodes）は"ユーザコード:権限"のペアをカンマ区切りで1行に保持する
# （client.batは1変数1行のため）。GUI側は行単位で追加・削除できるUIにするため、
# 選択中のグループの行データだけをメモリ上に保持し（$script:mentionRowsGroupNameで検知）、
# グループを切り替えたときだけファイルの値から読み直す
$mentionTypeOptions = @("USER", "GROUP", "ORGANIZATION")
$script:mentionRows = @()
$script:mentionRowsGroupName = $null
$script:mentionRowControls = @()

# collect-data-defs.txt（アプリデータ集計の列定義。[セクション見出し]＋「元の列名[,新しい列名]」の
# 表形式）を、行の追加・削除ができる表形式のUIで編集する。全グループ共通の内容なので共通タブの末尾に置く。
# セクション見出しはcommon-env.bat側のSourceType_<接尾辞>変数名（例: SourceType_Daily）をそのまま使う。
# 実際の出力ファイル名はその変数の値（業務日誌/パルスサーベイ等）が決めるため、画面の
# 「ファイル名」欄は値の参照表示のみ（編集不可）にする
$collectDataDefsPath = Join-Path $basePath "collect-data-defs.txt"
# $null=未読込（初回描画時にファイルから読み込む）。以降は編集中の内容をここに保持し、
# 行追加・削除のたびの再描画でも未保存の入力内容が消えないようにする
$script:collectDataDefsSections = $null
$script:collectDataDefsRowControls = @()

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

    foreach ($section in $script:collectDataDefsSections) {
        $lblFileNameCaption = New-Object System.Windows.Forms.Label
        $lblFileNameCaption.Text = "ファイル名"
        $lblFileNameCaption.AutoSize = $false
        $lblFileNameCaption.Size = New-Object System.Drawing.Size(220, 20)
        $lblFileNameCaption.Location = New-Object System.Drawing.Point(20, $y)
        $lblFileNameCaption.Font = New-Object System.Drawing.Font($lblFileNameCaption.Font.FontFamily, 9, [System.Drawing.FontStyle]::Bold)
        $settingsCommonFieldPanel.Controls.Add($lblFileNameCaption)

        $lblFileNameValue = New-Object System.Windows.Forms.Label
        $lblFileNameValue.Text = if ($script:commonEnvVars.ContainsKey($section.Key)) { $script:commonEnvVars[$section.Key] } else { $section.Key }
        $lblFileNameValue.AutoSize = $false
        $lblFileNameValue.Size = New-Object System.Drawing.Size(300, 20)
        $lblFileNameValue.Location = New-Object System.Drawing.Point(250, $y)
        $settingsCommonFieldPanel.Controls.Add($lblFileNameValue)
        $y += 26

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
        $lblNewHeader.Location = New-Object System.Drawing.Point(250, $y)
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
            $txtNew.Location = New-Object System.Drawing.Point(250, $y)
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
    $scrollX = -$settingsGroupFieldPanel.AutoScrollPosition.X
    $scrollY = -$settingsGroupFieldPanel.AutoScrollPosition.Y

    $target = $cmbSettingsGroupTarget.SelectedItem
    Render-SettingsFields -Panel $settingsGroupFieldPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target) -TextBoxes $script:settingsGroupFieldTextBoxes -TrailingButtonVars $settingsTrailingButtonVars | Out-Null

    $settingsGroupFieldPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

# 業務日誌/パルスサーベイの各セクションの「テスト接続」ボタン用。画面上の（未保存の）入力値を使って
# kintoneのフィールド取得APIを呼び、認証情報・対象アプリIDの組み合わせが有効かその場で確認する。
# TargetAppIdsはcreate-app-data.ps1のGet-FieldCodeListと同じくカンマ・空白区切りで複数指定できるため、
# 1つずつ個別に呼び分けて成功/失敗をID単位で表示する
function Test-KintoneConnection {
    param([string]$ReportGroup)

    $kintoneSubdomain = Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain"
    $kintoneLoginName = Get-GroupSettingsFieldValue "AUTH_KintoneLoginName"
    $kintonePassword = Get-GroupSettingsFieldValue "AUTH_KintonePassword"
    $targetAppIdsValue = Get-GroupSettingsFieldValue "${ReportGroup}_TargetAppIds"
    $targetAppIds = @($targetAppIdsValue -split '[,\s]+' | Where-Object { $_ })

    if ($targetAppIds.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("対象アプリIDが未入力です。", "テスト接続", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $baseUrl = "https://$kintoneSubdomain.cybozu.com"
    $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${kintoneLoginName}:${kintonePassword}"))

    # IDが複数になっても横に長くならないよう、1件1行の縦並びで表示する
    $resultLines = @()
    $hasFailure = $false
    foreach ($targetAppId in $targetAppIds) {
        try {
            $fieldData = Get-CurrentAppFieldData -TargetAppId $targetAppId -BaseUrl $baseUrl -Authorization $authorization
            $fieldCodes = @($fieldData.PSObject.Properties.Name)
            $resultLines += "[成功] $targetAppId（フィールド数: $($fieldCodes.Count)）"
            $resultLines += "  $($fieldCodes -join ', ')"
        } catch {
            $hasFailure = $true
            $resultLines += "[失敗] $targetAppId： $($_.Exception.Message)"
        }
    }

    $icon = if ($hasFailure) { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
    [System.Windows.Forms.MessageBox]::Show(($resultLines -join "`r`n"), "テスト接続", [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
}

# スペースID・スレッドID・メンション設定（投稿先）の妥当性は、スレッド単体を取得するAPIが無く
# メンション対象の存在確認にも別APIが必要になるため、実際にダミーコメントを投稿してみて確認する
function Test-KintonePostSettings {
    $kintoneSubdomain = Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain"
    $kintoneLoginName = Get-GroupSettingsFieldValue "AUTH_KintoneLoginName"
    $kintonePassword = Get-GroupSettingsFieldValue "AUTH_KintonePassword"
    $spaceId = Get-GroupSettingsFieldValue "POST_SpaceId"
    $threadId = Get-GroupSettingsFieldValue "POST_ThreadId"

    if ([string]::IsNullOrWhiteSpace($spaceId) -or [string]::IsNullOrWhiteSpace($threadId)) {
        [System.Windows.Forms.MessageBox]::Show("スペースIDとスレッドIDを入力してください。", "テスト投稿", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    Sync-MentionRowsFromControls
    $mentions = @($script:mentionRows | Where-Object { $_.Code } | ForEach-Object { @{ code = $_.Code; type = $_.Type } })

    $baseUrl = "https://$kintoneSubdomain.cybozu.com"
    $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${kintoneLoginName}:${kintonePassword}"))

    try {
        $response = Add-KintoneThreadComment -SpaceId $spaceId -ThreadId $threadId -Text "【テスト投稿】kintoneデータ集計ツールの設定確認用コメントです。不要であれば削除してください。" -Mentions $mentions -BaseUrl $baseUrl -Authorization $authorization
        [System.Windows.Forms.MessageBox]::Show("投稿に成功しました（コメントID: $($response.id)）。`r`nスレッドを確認し、不要であれば削除してください。", "テスト投稿", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("投稿に失敗しました。`r`n$($_.Exception.Message)", "テスト投稿", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

function Save-CommonSettings {
    $path = Join-Path $basePath "common-env.bat"

    # TargetDateCodeField_Daily等サフィックス付きの実際の行名→画面の入力欄キー（<Prefix>_xxx）の対応表
    $reportVarKeyMap = @{}
    foreach ($rt in (Get-ReportTypeDefs)) {
        foreach ($varName in $commonReportVars) {
            $reportVarKeyMap["$varName$($rt.Suffix)"] = "$($rt.Prefix)_$varName"
        }
    }

    $newLines = foreach ($line in [System.IO.File]::ReadAllLines($path, $script:cp932Encoding)) {
        $m = $script:groupBatLineRegex.Match($line.Trim())
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
    Sync-MentionRowsFromControls
    foreach ($varName in $postVars) {
        $val = if ($varName -eq "MentionUserCodes") {
            ConvertTo-MentionUserCodesText -Rows $script:mentionRows
        } else {
            Get-GroupSettingsFieldValue "POST_$varName"
        }
        if ($settingsMultilineVars -contains $varName) { $val = $val -replace "`r`n", '\n' -replace "`n", '\n' }
        $groupLines += "set `"$varName=$val`""
    }
    foreach ($rt in (Get-ReportTypeDefs)) {
        $groupLines += ""
        foreach ($varName in $groupReportVars) {
            $val = Get-GroupSettingsFieldValue "$($rt.Prefix)_$varName"
            $groupLines += "set `"$varName$($rt.Suffix)=$val`""
        }
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

$btnSettingsGroupNewGroup.Add_Click({
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

$lnkSettingsGroupOpenXlsx.Add_LinkClicked({
    $target = $cmbSettingsGroupTarget.SelectedItem
    if (!$target) {
        [System.Windows.Forms.MessageBox]::Show("対象グループが選択されていません。", "受講生データを開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    Open-TargetOrWarn -Path (Get-GroupXlsxPath $target)
})

$cmbSettingsGroupTarget.Add_SelectedIndexChanged({
    if (!$script:suppressComboSync) { Update-GroupSettingsFields }
})

# 外側タブ（実行/ログ/設定）はDock=Fillで常にフォーム全高を使うため、ここでは表示切り替えは不要で、
# タブ選択のたびに内容を最新化するだけでよい
$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabSettings) {
        Update-SettingsGroupList
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogView
    }
})

Update-SettingsGroupList
Update-CommonSettingsFields
Update-GroupSettingsFields

# ps2exeビルド環境ではタブの既定選択がずれることがあるため明示的に指定する
$execTabControl.SelectedTab = $tabBatchAll
$tabControl.SelectedTab = $tabRun

[System.Windows.Forms.Application]::Run($form)
