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
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施データ取得-テスト・アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "download-results.bat"); OpenTarget = $script:commonEnvVars["ClientDataRootDir"]; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "取得状況確認"; BatchLabel = "実施データ取得-取得状況確認"; IncludeInBatch = $false; BatchPath = (Join-Path $basePath "check-download-status.bat"); OpenTarget = $script:commonEnvVars["ResultRootDir"]; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "実施状況確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施状況確認-テスト・アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-combine-result.bat"); OpenTarget = $script:commonEnvVars["OutputCombineCollectDir"]; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "実施結果確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト"; BatchLabel = "実施結果確認-テスト"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-test-result.bat"); OpenTarget = $script:commonEnvVars["OutputTestCollectDir"]; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "アンケート"; BatchLabel = "実施結果確認-アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-survey-result.bat"); OpenTarget = $script:commonEnvVars["OutputSurveyCollectDir"]; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "投稿"; BatchLabel = "実施結果確認-投稿"; IncludeInBatch = $true; DefaultChecked = $false; BatchPath = (Join-Path $basePath "post-collect-results.bat"); OpenTarget = { param($groupName) Get-GroupKintoneThreadUrl -GroupName $groupName }; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "経年比較"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "アンケート・テスト"
                BatchLabel = "経年比較-アンケート・テスト"
                IncludeInBatch = $true
                DefaultChecked = $false
                BatchPath = (Join-Path $basePath "collect-year-comparison-result.bat")
                OpenTarget = $script:commonEnvVars["OutputYearComparisonCollectDir"]
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
# チェックボックスで対象ステップを選び、1つの実行ボタンで一括実行する）
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
        [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象グループ"; Options = $groupOptions; LabelWidth = 90; InputWidth = 150 }
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
$cmbBatchGroup = $batchTab.InputControls["TargetGroupNameFilter"]
$script:batchStepCheckboxes = $batchTab.CheckBoxes
$btnRunAll = $batchTab.RunButton
$lblBatchStatus = $batchTab.StatusLabel
$script:batchRunButtons = @($btnRunAll)

function Start-BatchRunAll {
    Invoke-BatchRunAll -ButtonDefs $allButtonDefs -CheckBoxes $script:batchStepCheckboxes `
        -StatusLabel $lblBatchStatus `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $basePath -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs {
                    param($bd)
                    $batArgs = @()
                    foreach ($inputDef in $bd.Inputs) {
                        $value = if ($inputDef.Name -eq "TargetGroupNameFilter") { Get-InputValue -Control $cmbBatchGroup } else { $inputDef.Default }
                        $batArgs += "$($inputDef.Name):$value"
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
                foreach ($inputName in $inputMap.Keys) {
                    $batArgs += "$($inputName):$(Get-InputValue -Control $inputMap[$inputName])"
                }
            }
            return $batArgs
        }
}
$script:runButtons = $tabResult.RunButtons

# 一括実行タブが既定の選択タブになるため、New-CategoryTabControl側で計算済みだった
# 初期の$execTabControl.Height（実施データ取得タブ基準）をこのタブの内容量に合わせて上書きする。
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

# 各.ps1はNew-WorkerLogPathで「<バッチ名>-<対象グループ>[-<対象年>]_<timestamp>.log」という
# ファイル名で書き出す（bats\library\common.ps1参照）。<バッチ名>はButtonDef.BatchPathの
# ファイル名（拡張子無し）と一致するため、それをそのままフィルタの接頭辞に使う
foreach ($radio in $script:logTab.Radios) {
    $radio.Add_CheckedChanged({ if ($this.Checked) { Update-LogView } })
}
$cmbLogGroup.Add_SelectedIndexChanged({ Update-LogView })

Update-LogView

# =========================================
# 設定タブ（kintone-aggregatorの設定タブと同様のレイアウト：
# 「共通」「グループ別」のサブタブに分けて編集する）
#
# 「共通」タブはcommon-env.bat（対象年度に関わらず共通のパス・既定値設定）を直接編集する。
# 「グループ別」タブはグループを選ぶと、そのグループのclients\<グループ名>.bat（認証情報）を編集する。
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

# 設定タブの各フィールドの生の値には、common-env.bat内の%BASE_PATH%や%OutputRootDir%のような
# %VAR%トークンがそのまま残っている（%~dp0のようなバッチ専用トークンは.NET側では解決できないため、
# common-env.bat側は%BASE_PATH%を使う方式に統一済み）。$script:commonEnvVars（起動時に
# common-env.batを実際に実行して解決済みの値）を使って再帰的に展開する
$script:commonEnvResolver = { param($name) $script:commonEnvVars[$name] }

# TargetYearはcommon-env.bat内でpowershellコマンドから動的に計算される特殊な行（set "VAR=value"形式
# ではない）ため、このリストにも$script:groupBatLineRegexにも掛からず編集対象にならない（既存の行はそのまま保持される）
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
$authVars = @("KintoneLoginName", "KintonePassword", "KintoneSubdomain")
$postVars = @("SpaceId", "ThreadId", "MentionUserCodes", "CommentTextTemplate")
$settingsMaskedVars = @("KintonePassword")
# client.batは1変数1行(set "Var=Value")の形式で改行を持てないため、複数行入力欄は
# 保存時に実際の改行を"\n"リテラルへ変換して1行に収め、画面表示時・スクリプト側の利用時に戻す
$settingsMultilineVars = @("CommentTextTemplate")
# 共通設定（common-env.bat）の既定値をグループ単位で上書きしたい項目。
# clients\<グループ名>.batはcommon-env.batの後にcallされるため、ここで値を書けばそのグループだけ上書きされる。
# 空欄のまま保存した場合はこの3行自体を書き出さない（空文字を上書きしてしまうと共通設定側の値が
# 効かなくなるため、「未指定＝共通設定の値を使う」を「行を書かない」で表す）
$groupOverrideVars = @("ComparePeriod", "YearOrder", "PassScore")

# テキスト入力ではなくラジオボタンで選ばせたい項目の、値とラベルの対応。
# Render-SettingsFields側はVarNameがこの辞書にあるかどうかだけを見るため、
# 今後ラジオボタン化したい項目が増えても、ここに1エントリ追加するだけで済む
$radioVars = @{
    "YearOrder" = @(
        [PSCustomObject]@{ Value = "0"; Label = "昇順(0)" }
        [PSCustomObject]@{ Value = "1"; Label = "降順(1)" }
    )
}

$settingsGroupLabels = @{ "COMMON" = "共通設定"; "AUTH" = "認証情報"; "POST" = "投稿先"; "OVERRIDE" = "個別設定（空欄の場合は共通設定の値を使用）" }
$settingsVarLabels = @{
    "KintoneLoginName"                = "ログイン名"
    "KintonePassword"                 = "パスワード"
    "SpaceId"                         = "投稿先スペースID"
    "ThreadId"                        = "投稿先スレッドID"
    "MentionUserCodes"                = "メンション対象"
    "CommentTextTemplate"             = "投稿コメント文言"
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

# 設定タブ自体は「共通」「グループ別」の2つのサブタブに分ける（共通設定の項目が増えてきて
# ドロップダウンでの切り替えより独立したタブの方が分かりやすいため）
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

# Label/LinkLabelはAutoSizeによる実際のHeightが親へのAddより前だと仮の値のままで、
# 親に追加された後でないと正しい値に確定しない。TextBox/ComboBoxも指定したHeightを
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

function Get-CommonSettingsFieldRows {
    $raw = Get-SetLineRawValues -Path (Join-Path $basePath "common-env.bat")
    foreach ($varName in $commonSettingsVars) {
        [PSCustomObject]@{ Key = $varName; VarName = $varName; Group = "COMMON"; Value = $raw[$varName] }
    }
}

function Get-GroupSettingsFieldRows {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $templateDefaults = Get-GroupTemplateDefaults
    $rawAuth = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)
    foreach ($varName in $authVars) {
        $value = if ($rawAuth.ContainsKey($varName)) { $rawAuth[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "AUTH_$varName"; VarName = $varName; Group = "AUTH"; Value = $value }
    }
    foreach ($varName in $postVars) {
        $value = if ($rawAuth.ContainsKey($varName)) { $rawAuth[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "POST_$varName"; VarName = $varName; Group = "POST"; Value = $value }
    }
    # 上書き項目は共通設定・テンプレートの値にはフォールバックしない。「空欄」がそのまま
    # 「このグループでは上書きしていない」を表す（Save-GroupSettings側も参照）
    foreach ($varName in $groupOverrideVars) {
        $value = if ($rawAuth.ContainsKey($varName)) { $rawAuth[$varName] } else { "" }
        [PSCustomObject]@{ Key = "OVERRIDE_$varName"; VarName = $varName; Group = "OVERRIDE"; Value = $value }
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


function Update-CommonSettingsFields {
    Render-SettingsFields -Panel $settingsCommonFieldPanel -Rows (Get-CommonSettingsFieldRows) -TextBoxes $script:settingsCommonFieldTextBoxes -RadioVars $radioVars | Out-Null
}

function Update-GroupSettingsFields {
    # メンション設定の行追加・削除のたびに再描画されるため、スクロール位置がリセットされないよう保存・復元する
    $scrollX = -$settingsGroupFieldPanel.AutoScrollPosition.X
    $scrollY = -$settingsGroupFieldPanel.AutoScrollPosition.Y

    $target = $cmbSettingsGroupTarget.SelectedItem
    Render-SettingsFields -Panel $settingsGroupFieldPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target) -TextBoxes $script:settingsGroupFieldTextBoxes -RadioVars $radioVars -TrailingButtonVars @{ "CommentTextTemplate" = { param($Panel, $Y, $Field) Add-TestPostButton -Panel $Panel -Y $Y -ToolName "track-aggregator" } } | Out-Null

    $settingsGroupFieldPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

function Save-CommonSettings {
    $path = Join-Path $basePath "common-env.bat"
    $newLines = foreach ($line in [System.IO.File]::ReadAllLines($path, $script:cp932Encoding)) {
        $m = $script:groupBatLineRegex.Match($line.Trim())
        if ($m.Success -and ($commonSettingsVars -contains $m.Groups["var"].Value)) {
            $varName = $m.Groups["var"].Value
            $val = Get-CommonSettingsFieldValue $varName
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

    # Authorizationは画面上の編集項目からは外したが、実行スクリプト側は今も参照するため、
    # 上書き前の既存の値をそのまま引き継ぐ（新規グループはclients\template\の既定値＝空欄になる）
    $existingAuth = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)
    $authorizationValue = if ($existingAuth.ContainsKey("Authorization")) { $existingAuth["Authorization"] } else { (Get-GroupTemplateDefaults).Auth["Authorization"] }

    $authLines = @("@echo off", "")
    foreach ($varName in $authVars) {
        $val = Get-GroupSettingsFieldValue "AUTH_$varName"
        $authLines += "set `"$varName=$val`""
    }
    $authLines += "set `"Authorization=$authorizationValue`""
    # BaseUrlは画面では編集させず、KintoneSubdomainから常に導出する
    $authLines += "set `"BaseUrl=https://%KintoneSubdomain%.cybozu.com`""
    $authLines += ""

    Sync-MentionRowsFromControls
    foreach ($varName in $postVars) {
        $val = if ($varName -eq "MentionUserCodes") {
            ConvertTo-MentionUserCodesText -Rows $script:mentionRows
        } else {
            Get-GroupSettingsFieldValue "POST_$varName"
        }
        if ($settingsMultilineVars -contains $varName) { $val = $val -replace "`r`n", '\n' -replace "`n", '\n' }
        $authLines += "set `"$varName=$val`""
    }
    $authLines += ""

    # 上書き項目は空欄なら行自体を書かない（空文字を上書きすると共通設定側の値が効かなくなるため）
    foreach ($varName in $groupOverrideVars) {
        $val = Get-GroupSettingsFieldValue "OVERRIDE_$varName"
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

$btnSettingsCommonSave.Add_Click({
    Save-CommonSettings
    Update-CommonSettingsFields
    $lblSettingsCommonSaveStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblSettingsCommonSaveStatus.Text = "保存しました"
})

$btnSettingsCommonReload.Add_Click({
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

    if ($cmbSettingsGroupTarget.Items.Contains($newName) -or (Get-GroupXlsxFiles -GroupName $newName).Count -gt 0 -or (Test-Path -LiteralPath (Get-GroupBatPath $newName))) {
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
    Open-TargetOrWarn -Path $openPath
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
