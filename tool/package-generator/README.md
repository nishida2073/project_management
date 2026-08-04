# 個社別ZIP生成ツール

## 概要

`config\package_definition.xlsx` の内容に従って、シートごとにファイルを集めてZIP化するツール。
Excelの書き方は[config\README.md](config/README.md)を参照。

パス関連の設定は `SetEnv.bat` にまとめてある。PowerShellスクリプト（`GeneratePackage.ps1` / `SyncFolder.ps1`）を直接編集せずに、`SetEnv.bat` の内容を書き換えるか、実行前に環境変数を設定することで変更できる。すでに環境変数が設定されている場合はそれが優先され、`SetEnv.bat` の値は上書きしない（`if not defined` 方式）。

## 環境変数（共通）

共通して使う変数。

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `COMMON_WORK_PATH` | コピー作業用の一時フォルダ（実行時に毎回削除→再作成される） | `work` フォルダ |
| `COMMON_OUTPUT_PATH` | 最終成果物の出力先フォルダ | `output` フォルダ |
| `COMMON_LOG_PATH` | log の出力先フォルダ | `log` フォルダ |

## ファイル同期について

取得元（`GENERATE_SOURCE_BASE`配下）にコピーしたいファイルがTeams/SharePoint上にある場合、`SyncFolder.bat`で事前にローカルへダウンロードできる。OneDriveの同期クライアントは使わず、Azure CLIで取得したトークンでMicrosoft Graph APIから直接取得する。

処理の流れ：

```
SyncFolder.bat
  → SetEnv.bat を呼び出し、環境変数の初期値をセット
  → SyncFolder.ps1 を実行
      - Azure CLIでサインイン（未サインイン・期限切れ時はデバイスコードでログイン）
      - Microsoft Graph APIでサイトを解決し、指定フォルダ配下を再帰的にローカルへダウンロード
```

### 環境変数（ファイル同期）

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `SYNC_SITE_URL` | 取得元のSharePointサイトURL（例：`https://xxx.sharepoint.com/sites/チーム名`） | 空（必須設定） |
| `SYNC_FOLDER` | サイト内の取得元フォルダ（先頭はドキュメントライブラリ名、例：`Shared Documents/ClientA`） | 空（必須設定） |
| `SYNC_TENANT_ID` | 対象のAzure ADテナントID | 空（必須設定） |
| `SYNC_LOCAL_DEST` | ダウンロード先のローカルフォルダ（フルパス、または`GENERATE_SOURCE_BASE`からの相対パス） | 空の場合、`GENERATE_SOURCE_BASE`配下に`SYNC_FOLDER`の末尾フォルダ名で作成 |
| `SYNC_LOG_PREFIX` | ログファイル名（`<ダウンロード先フォルダ名>.log`）の先頭に付けるプレフィックス | 空（なし） |

`SYNC_LOCAL_DEST`を省略するか、相対パス（例：`sync`）で指定すると、`GENERATE_SOURCE_BASE`配下に置かれるので、そのままExcelの「取得元（フルパス）」列から相対パスで参照できる。ドライブ文字や`\\`から始まるフルパスを指定した場合はそのまま使われる。

### 出力ファイル

ダウンロード先フォルダ名と同じ名前で、`log`フォルダ（`COMMON_LOG_PATH`）に処理ログを出力する。`GENERATE_LOG_PREFIX`とは別に、こちらは`SYNC_LOG_PREFIX`で個別にプレフィックスを設定できる。

```
# 取得結果
  実際にダウンロードした「ファイル名 -> ローカルの保存先」の一覧

# 最終結果
  ダウンロードしたフォルダの最終的な構成（ツリー表示）
```

### 必要なもの・注意点

- **Azure CLI**が必要（`winget install --id Microsoft.AzureCLI`）。未インストールの場合、`SyncFolder.ps1`がエラーで案内を表示して終了する。
- 初回、またはサインインが切れている場合はデバイスコードでのログインが必要（URLとコードがコンソールに表示されるので、ブラウザで開いて入力する）。テナントの条件付きアクセス設定によってはMFAが必要になる場合がある。
  - サブスクリプションを持っていないアカウントでも、`--allow-no-subscriptions`でサインインするため問題ない。
- 大量のファイル・深いフォルダ構成があると取得に時間がかかる。

## zip作成について

`GeneratePackage.bat` をダブルクリックして実行する。

処理の流れ：

```
GeneratePackage.bat
  → SetEnv.bat を呼び出し、環境変数の初期値をセット
  → GeneratePackage.ps1 を実行
      - config\package_definition.xlsx を読み込み
      - シートごとにファイルをコピー・ZIP化
      - output フォルダに zip、log フォルダに log を出力
```

### 環境変数（zip作成）

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `GENERATE_SOURCE_BASE` | Excelの「取得元（フルパス）」列を相対パスで書いたときの共通の親フォルダ（※ドライブ文字や`\\`から始まるフルパスの行には影響しない） | このツール自体のフォルダ |
| `GENERATE_CONFIG_PATH` | `package_definition.xlsx` のパス | `config\package_definition.xlsx` |
| `GENERATE_SHEETS_INCLUDE` | 処理対象にするシート名（カンマ区切り、複数指定可）。設定時はここに書いたシートのみ処理する | 空（絞り込みなし＝全シート対象） |
| `GENERATE_SHEETS_EXCLUDE` | 処理対象から除外するシート名（カンマ区切り、複数指定可） | 空（除外なし） |
| `GENERATE_LOG_PREFIX` | ログファイル名（`<シート名>.log`）の先頭に付けるプレフィックス | 空（なし） |

`GENERATE_SHEETS_INCLUDE` / `GENERATE_SHEETS_EXCLUDE` は `GeneratePackage.bat` の引数でも指定できる（環境変数より優先される）。

```
GeneratePackage.bat "include=対象シート1,対象シート2"
GeneratePackage.bat "exclude=除外シート1,除外シート2"
GeneratePackage.bat "include=対象シート1" "exclude=除外シート1"
```

`include=` / `exclude=` は順不同で、どちらか片方だけの指定もできる。両方指定した場合は、対象シートに絞り込んだ後にさらに除外シートを取り除く。

### 出力ファイル

シートごとに、ZIPと処理ログを別フォルダに出力する。

| ファイル | 出力先 | 内容 |
|---|---|---|
| `<シート名>.zip` | `output` フォルダ | コピーしたファイル一式をまとめたZIP |
| `<シート名>.log` | `log` フォルダ | 処理内容のログ（下記） |

```
# コピー結果
  実際にコピーした「元パス -> 先パス」の一覧

# 最終結果
  ZIPに実際に含まれる最終的なフォルダ構成（ツリー表示）
```

対象ファイルが1件も無かったシートは、ZIP/ログとも出力されない。

### 必要なもの

PowerShellモジュール「ImportExcel」が必要。未インストールの場合、実行時に自動でインストールされる（初回はインターネット接続とインストール確認が必要）。
