# 個社別ZIP生成ツール

## 概要

大まかな流れは以下の3段階。

1. Teams/SharePoint上の素材をローカルにダウンロード（[1. ファイルダウンロードについて](#1-ファイルダウンロードについて)）
2. ダウンロードした素材からExcelの設定に従って個別パッケージ（ZIP）を作成（[2. 個別パッケージの作成について](#2-個別パッケージの作成について)）
3. 作成したパッケージをTeams/SharePointにアップロード（[3. ファイルアップロードについて](#3-ファイルアップロードについて)）

パス関連の設定は `SetEnv.bat` にまとめてある。PowerShellスクリプト（`GeneratePackage.ps1` / `DownloadFolder.ps1` / `UploadFolder.ps1`）を直接編集せずに、`SetEnv.bat` の内容を書き換えるか、実行前に環境変数を設定することで変更できる。すでに環境変数が設定されている場合はそれが優先され、`SetEnv.bat` の値は上書きしない（`if not defined` 方式）。

`Common.ps1`は上記3つのスクリプトが共通で使う関数（フォルダ構成のツリー表示、Azure CLI/Microsoft Graph関連の処理）をまとめたファイルで、各スクリプトの先頭でドットソースして読み込まれる。直接実行するものではない。

## 環境変数（共通）

共通して使う変数。

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `COMMON_LOG_PATH` | log の出力先フォルダ | `log` フォルダ |

## 1. ファイルダウンロードについて

取得元（`GENERATE_SOURCE_BASE`配下）にコピーしたいファイルがTeams/SharePoint上にある場合、`DownloadFolder.bat`で事前にローカルへダウンロードできる。OneDriveの同期クライアントは使わず、Azure CLIで取得したトークンでMicrosoft Graph APIから直接取得する。

処理の流れ：

```
DownloadFolder.bat
  → SetEnv.bat を呼び出し、環境変数の初期値をセット
  → DownloadFolder.ps1 を実行
      - Azure CLIでサインイン（未サインイン・期限切れ時はデバイスコードでログイン）
      - Microsoft Graph APIでサイトを解決し、指定フォルダ配下を再帰的にローカルへダウンロード
```

### 環境変数（ダウンロード）

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `DOWNLOAD_SITE_URL` | 取得元のSharePointサイトURL（例：`https://xxx.sharepoint.com/sites/チーム名`） | テスト用サイトのURLが設定済み |
| `DOWNLOAD_FOLDER` | サイト内の取得元フォルダ（先頭はドキュメントライブラリ名、例：`Shared Documents/フォルダA`） | テスト用フォルダ（`.../ツール/原本`）が設定済み |
| `DOWNLOAD_TENANT_ID` | 対象のAzure ADテナントID | テスト用テナントIDが設定済み |
| `DOWNLOAD_LOCAL_DEST` | ダウンロード先のローカルフォルダ（フルパス、または`GENERATE_SOURCE_BASE`からの相対パス） | `download` フォルダ |
| `DOWNLOAD_LOG_PREFIX` | ログファイル名（`<ダウンロード先フォルダ名>.log`）の先頭に付けるプレフィックス | `ダウンロード_` |

`DOWNLOAD_LOCAL_DEST`を省略するか、相対パス（例：`download`）で指定すると、`GENERATE_SOURCE_BASE`配下に置かれるので、そのままExcelの「取得元（フルパス）」列から相対パスで参照できる。ドライブ文字や`\\`から始まるフルパスを指定した場合はそのまま使われる。

同名のローカルファイルが既にある場合は上書きされる。

### 出力ファイル

ダウンロード先フォルダ名と同じ名前で、`log`フォルダ（`COMMON_LOG_PATH`）に処理ログを出力する。

```
# 取得結果
  実際にダウンロードした「ファイル名 -> ローカルの保存先」の一覧

# フォルダ構成
  ダウンロードしたフォルダの最終的な構成（ツリー表示）
```

### 必要なもの・注意点

- **Azure CLI**が必要（`winget install --id Microsoft.AzureCLI`）。未インストールの場合、`DownloadFolder.ps1`がエラーで案内を表示して終了する。
- 初回、またはサインインが切れている場合はデバイスコードでのログインが必要（URLとコードがコンソールに表示されるので、ブラウザで開いて入力する）。テナントの条件付きアクセス設定によってはMFAが必要になる場合がある。
  - サブスクリプションを持っていないアカウントでも、`--allow-no-subscriptions`でサインインするため問題ない。
- 大量のファイル・深いフォルダ構成があると取得に時間がかかる。
- ダウンロード先フォルダは自動でクリーンされない（SharePoint側で削除されたファイルもローカルには残り続ける）。SharePoint側と完全に一致させたい場合は、実行前に`DOWNLOAD_LOCAL_DEST`の中身を自分で削除しておくこと。

## 2. 個別パッケージの作成について

`config\package_definition.xlsx` の内容に従って、シートごとにファイルを集めてZIP化する。
Excelの書き方は[config\README.md](config/README.md)を参照。

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

### 環境変数（個別パッケージの作成）

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `GENERATE_SOURCE_BASE` | Excelの「取得元（フルパス）」列を相対パスで書いたときの共通の親フォルダ（※ドライブ文字や`\\`から始まるフルパスの行には影響しない） | `DOWNLOAD_LOCAL_DEST`と同じ（ダウンロードしたフォルダ） |
| `GENERATE_CONFIG_PATH` | `package_definition.xlsx` のパス | `config\package_definition.xlsx` |
| `GENERATE_WORK_PATH` | コピー作業用の一時フォルダ（実行時に毎回削除→再作成される） | `work` フォルダ |
| `GENERATE_OUTPUT_PATH` | 成果物の出力先フォルダ | `output` フォルダ |
| `GENERATE_SHEETS_INCLUDE` | 処理対象にするシート名（カンマ区切り、複数指定可）。設定時はここに書いたシートのみ処理する | 空（絞り込みなし＝全シート対象） |
| `GENERATE_SHEETS_EXCLUDE` | 処理対象から除外するシート名（カンマ区切り、複数指定可） | 空（除外なし） |
| `GENERATE_LOG_PREFIX` | ログファイル名（`<シート名>.log`）の先頭に付けるプレフィックス | `パッケージング_` |

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

# フォルダ構成
  ZIPに実際に含まれる最終的なフォルダ構成（ツリー表示）
```

対象ファイルが1件も無かったシートは、ZIP/ログとも出力されない。

`output`フォルダ自体は自動でクリーンされない（各シートのZIPはそのシート処理時に個別に削除→再作成されるが、Excelから削除・リネームしたシートの古いZIPは残り続ける）。不要になった古いZIPを残したくない場合は、実行前に`GENERATE_OUTPUT_PATH`の中身を自分で削除しておくこと。

### 必要なもの

PowerShellモジュール「ImportExcel」が必要。未インストールの場合、実行時に自動でインストールされる（初回はインターネット接続とインストール確認が必要）。

## 3. ファイルアップロードについて

ローカルフォルダの中身をTeams/SharePointにアップロードしたい場合、`UploadFolder.bat`で送信できる。`DownloadFolder.bat`の逆方向で、同じくAzure CLIで取得したトークンでMicrosoft Graph APIから直接アップロードする（ファイルサイズの上限を避けるため、常にアップロードセッション＝チャンク方式で送信する）。

処理の流れ：

```
UploadFolder.bat
  → SetEnv.bat を呼び出し、環境変数の初期値をセット
  → UploadFolder.ps1 を実行
      - Azure CLIでサインイン（未サインイン・期限切れ時はデバイスコードでログイン）
      - Microsoft Graph APIでサイトを解決し、ローカルフォルダ配下を再帰的にアップロード
```

### 環境変数（アップロード）

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `UPLOAD_SITE_URL` | アップロード先のSharePointサイトURL（例：`https://xxx.sharepoint.com/sites/チーム名`） | `DOWNLOAD_SITE_URL`と同じ |
| `UPLOAD_FOLDER` | サイト内のアップロード先フォルダ（先頭はドキュメントライブラリ名、例：`Shared Documents/フォルダA`） | テスト用フォルダ（`.../ツール/納品`）が設定済み |
| `UPLOAD_TENANT_ID` | 対象のAzure ADテナントID | `DOWNLOAD_TENANT_ID`と同じ |
| `UPLOAD_LOCAL_SOURCE` | アップロード元のローカルフォルダ（フルパス） | `GENERATE_OUTPUT_PATH`と同じ（zip作成の出力先） |
| `UPLOAD_LOG_PREFIX` | ログファイル名（`<アップロード元フォルダ名>.log`）の先頭に付けるプレフィックス | `アップロード_` |

同名ファイルが既にサイト側にある場合は上書きされる。

### 出力ファイル

アップロード元フォルダ名と同じ名前で、`log`フォルダ（`COMMON_LOG_PATH`）に処理ログを出力する。

```
# アップロード結果
  実際にアップロードした「ローカルのパス -> サイト内の格納先」の一覧

# フォルダ構成
  アップロード元フォルダの構成（ツリー表示）
```

### 必要なもの・注意点

- **Azure CLI**が必要（`winget install --id Microsoft.AzureCLI`）。未インストールの場合、`UploadFolder.ps1`がエラーで案内を表示して終了する。
- 初回、またはサインインが切れている場合はデバイスコードでのログインが必要（`DownloadFolder.bat`と同様）。
- SharePoint側のアップロード用エンドポイントとの通信が不安定な場合があり、1チャンクにつき最大8回リトライする。
- 大量のファイル・深いフォルダ構成があると時間がかかる。
