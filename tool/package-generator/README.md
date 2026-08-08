# コース別パッケージ生成ツール

## 概要

### 実施手順

1. Teams/SharePoint上の素材をローカルにダウンロード（[1. ファイルダウンロードについて](#1-ファイルダウンロードについて)）
2. ダウンロードした素材からExcelの設定に従って個別パッケージを作成（[2. 個別パッケージの作成について](#2-個別パッケージの作成について)）
3. 作成したパッケージをTeams/SharePointにアップロード（[3. ファイルアップロードについて](#3-ファイルアップロードについて)）

`all.bat`を実行すると、上記3段階を`clients\set-env.bat`を呼び出した上でこの順に続けて実行する。いずれかの段階が失敗した場合はそこで中断し、後続の段階は実行しない。各段階は`DOWNLOAD_ENABLED` / `GENERATE_ENABLED` / `UPLOAD_ENABLED`で有効/無効を切り替えられる（`UPLOAD_ENABLED`は既定で`0`＝無効、他は既定で`1`＝有効。[環境変数](#環境変数)を参照）。

## ツールの構成

| ファイル/フォルダ | 役割 |
|---|---|
| `all.bat` | 3段階（ダウンロード→パッケージ作成→アップロード）を続けて実行するエントリーポイント |
| `download-folder.bat` | 「1. ファイルダウンロード」のエントリーポイント |
| `generate-package.bat` | 「2. 個別パッケージの作成」のエントリーポイント |
| `upload-folder.bat` | 「3. ファイルアップロード」のエントリーポイント |
| `scripts\common.ps1` | 3つの`.ps1`が共通で使う関数（フォルダ構成のツリー表示、Azure CLI/Microsoft Graph関連の処理）。各`.ps1`の先頭でドットソースして読み込まれる。ユーザーが直接実行するものではない |
| `scripts\download-folder.ps1` / `generate-package.ps1` / `upload-folder.ps1` | 各段階の実装本体（`.bat`から呼び出される。ユーザーが直接実行するものではない） |
| `package_definition.xlsx` | パッケージ定義ファイル。書き方は[config\README.md](config/README.md)を参照 |
| `build-gui.bat` | GUI版（`コース別パッケージ生成ツール.exe`）をビルドするエントリーポイント。[GUI版](#gui版)を参照 |
| `scripts\gui.ps1` / `build-gui.ps1` | GUI版の画面本体、およびそれをexe化するビルドスクリプト（`build-gui.bat`から呼び出される。ユーザーが直接実行するものではない） |
| `clients\set-env.bat` | 環境変数の初期値をまとめて設定する（他の`.bat`から`call clients\set-env.bat`される） |
| `clients\set-env-<クライアント名>.bat` | クライアントごとの上書き設定ファイル（GUI版の「実行」「ログ」「設定」タブの「クライアント」ドロップダウンから選ぶ）。書き方は[clients\README.md](clients/README.md)を参照 |

パス関連の設定は `clients\set-env.bat` にまとめてある。PowerShellスクリプト（`generate-package.ps1` / `download-folder.ps1` / `upload-folder.ps1`）を直接編集せずに、`clients\set-env.bat` の内容を書き換えるか、実行前に環境変数を設定することで変更できる。すでに環境変数が設定されている場合はそれが優先され、`clients\set-env.bat` の値は上書きしない（`if not defined` 方式）。

## Azure CLIでのサインイン

`download-folder.ps1`と`upload-folder.ps1`は共通してAzure CLIでサインインし、そのトークンでMicrosoft Graph APIを直接呼び出す（`common.ps1`に集約）。初回、またはサインインが切れている場合はデバイスコードでのログインが必要（URLとコードがコンソールに表示されるので、ブラウザで開いて入力する）。テナントの条件付きアクセス設定によってはMFAが必要になる場合がある。サブスクリプションを持っていないアカウントでも`--allow-no-subscriptions`でサインインするため問題ない。

## 処理の詳細

### 環境変数

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `COMMON_LOG_PATH` | ログの出力先フォルダ | `log` フォルダ |
| `DOWNLOAD_ENABLED` | `all.bat`実行時に「1. ファイルダウンロード」を実行するかどうか（`0`にすると無効化） | `1`（有効） |
| `GENERATE_ENABLED` | `all.bat`実行時に「2. 個別パッケージの作成」を実行するかどうか（`0`にすると無効化） | `1`（有効） |
| `UPLOAD_ENABLED` | `all.bat`実行時に「3. ファイルアップロード」を実行するかどうか（`1`にすると有効化） | `0`（無効） |

### 1. ファイルダウンロードについて

コピーしたいファイルがTeams/SharePoint上にある場合、`download-folder.bat`で事前にローカルへダウンロードできる。OneDriveの同期クライアントは使わず、Azure CLIで取得したトークンでMicrosoft Graph APIから直接取得する。

#### 処理の流れ

1. `download-folder.bat` を実行する
2. `clients\set-env.bat` が呼び出され、環境変数の初期値がセットされる
3. `download-folder.ps1` が実行される
   1. Azure CLIでサインインする（未サインイン・期限切れ時はデバイスコードでのログインが必要）
   2. Microsoft Graph APIでサイト（`DOWNLOAD_SITE_URL`）を解決する
   3. 指定フォルダ（`DOWNLOAD_SITE_PATH`）配下を再帰的にローカルフォルダ（`DOWNLOAD_LOCAL_PATH`）へダウンロードする
   4. ログの出力先（`COMMON_LOG_PATH`）に処理ログを出力する

#### 環境変数

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `DOWNLOAD_SITE_URL` | ダウンロード元のSharePointサイトURL（例：`https://xxx.sharepoint.com/sites/チーム名`） | テスト用サイトのURLが設定済み |
| `DOWNLOAD_SITE_PATH` | サイト内のダウンロード元フォルダ（先頭はドキュメントライブラリ名、例：`Shared Documents/フォルダA`） | テスト用フォルダ（`.../ツール/原本`）が設定済み |
| `DOWNLOAD_SITE_TENANT_ID` | 対象のAzure ADテナントID | テスト用テナントIDが設定済み |
| `DOWNLOAD_LOCAL_PATH` | ダウンロード先のローカルフォルダ（フルパス、または`GENERATE_SOURCE_PATH`からの相対パス） | `download` フォルダ |
| `DOWNLOAD_LOG_PREFIX` | ログファイル名（`<ダウンロード元のフォルダ名>.log`）の先頭に付けるプレフィックス | `ダウンロード_` |

`DOWNLOAD_LOCAL_PATH`を省略するか、相対パス（例：`download`）で指定すると、`GENERATE_SOURCE_PATH`配下に置かれるので、そのままExcelの「取得元（フルパス）」列から相対パスで参照できる。ドライブ文字や`\`から始まるフルパス（`\\`から始まるUNCパスも含む）を指定した場合はそのまま使われる。

同名のローカルファイルが既にある場合は上書きされる。

#### 出力結果

| ファイル | 出力先 | 内容 |
|---|---|---|
| ダウンロードしたファイル一式 | ダウンロード先（`DOWNLOAD_LOCAL_PATH`） | SharePointからダウンロードしたファイル・フォルダ |
| `<ダウンロード元のフォルダ名>.log` | ログの出力先（`COMMON_LOG_PATH`） | 処理内容のログ（実際のファイル名には`<クライアント名または"デフォルト">_`も挟まる。詳しくは[clients\README.md](clients/README.md)を参照） |

#### 必要なもの

> **Azure CLI**が必要（`winget install --id Microsoft.AzureCLI`）。未インストールの場合、`download-folder.ps1`がエラーで案内を表示して終了する。サインイン方法は[Azure CLIでのサインイン](#azure-cliでのサインイン)を参照。

#### 注意点

> 大量のファイル・深いフォルダ構成があると取得に時間がかかる。

> ダウンロード先フォルダは自動でクリーンされない（SharePoint側で削除されたファイルもローカルには残り続ける）。SharePoint側と完全に一致させたい場合は、実行前に`DOWNLOAD_LOCAL_PATH`の中身を自分で削除しておくこと。

### 2. 個別パッケージの作成について

パッケージ定義ファイル（`GENERATE_CONFIG_PATH`）の内容に従って、シートごとにファイルを集めてパッケージ化する。
Excelの書き方は[config\README.md](config/README.md)を参照。

#### 処理の流れ

1. `generate-package.bat` を実行する
2. `clients\set-env.bat` が呼び出され、環境変数の初期値がセットされる
3. `generate-package.ps1` が実行される
   1. パッケージ定義ファイル（`GENERATE_CONFIG_PATH`、既定は`download\package_definition.xlsx`）を読み込む
   2. シートごとにファイルをコピーしてパッケージ化する
   3. パッケージの出力先（`GENERATE_OUTPUT_PATH`）にパッケージ、ログの出力先（`COMMON_LOG_PATH`）に処理ログを出力する
   4. パッケージ定義ファイル自体もパッケージの出力先（`GENERATE_OUTPUT_PATH`）にコピーする

#### 環境変数

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `GENERATE_SOURCE_PATH` | 圧縮元のフォルダ | `DOWNLOAD_LOCAL_PATH`と同じ（ダウンロードしたフォルダ） |
| `GENERATE_CONFIG_PATH` | パッケージ定義ファイル（`package_definition.xlsx`）のパス | `download\package_definition.xlsx`（`DOWNLOAD_LOCAL_PATH`配下） |
| `GENERATE_WORK_PATH` | コピー作業用の一時フォルダ | `work` フォルダ |
| `GENERATE_OUTPUT_PATH` | パッケージの出力先フォルダ | `generated` フォルダ |
| `GENERATE_SHEETS_INCLUDE` | 処理対象にするシート名（カンマ区切り、複数指定可）。設定時はここに書いたシートのみ処理する | 空（絞り込みなし＝全シート対象） |
| `GENERATE_SHEETS_EXCLUDE` | 処理対象から除外するシート名（カンマ区切り、複数指定可） | 空（除外なし） |
| `GENERATE_LOG_PREFIX` | ログファイル名（`<シート名>.log`）の先頭に付けるプレフィックス | `パッケージ作成_` |

`GENERATE_SHEETS_INCLUDE` / `GENERATE_SHEETS_EXCLUDE` は `generate-package.bat` の引数でも指定できる（環境変数より優先される）。

```
generate-package.bat "include=対象シート1,対象シート2"
generate-package.bat "exclude=除外シート1,除外シート2"
generate-package.bat "include=対象シート1" "exclude=除外シート1"
```

`include=` / `exclude=` は順不同で、どちらか片方だけの指定もできる。両方指定した場合は、対象シートに絞り込んだ後にさらに除外シートを取り除く。

#### 出力結果

シートごとに、パッケージと処理ログを別フォルダに出力する。

| ファイル | 出力先 | 内容 |
|---|---|---|
| `<シート名>.zip` | パッケージの出力先（`GENERATE_OUTPUT_PATH`） | コピーしたファイル一式をまとめたパッケージ |
| `<シート名>.log` | ログの出力先（`COMMON_LOG_PATH`） | 処理内容のログ（実際のファイル名には`<クライアント名または"デフォルト">_`も挟まる。詳しくは[clients\README.md](clients/README.md)を参照） |
| パッケージ定義ファイルのコピー | パッケージの出力先（`GENERATE_OUTPUT_PATH`） | 実行時に使われた`GENERATE_CONFIG_PATH`のファイルそのもの |

対象ファイルが1件も無かったシートは、パッケージ/ログとも出力されない。

#### 必要なもの

> PowerShellモジュール「ImportExcel」が必要。未インストールの場合、実行時に自動でインストールされる（初回はインターネット接続とインストール確認が必要）。

#### 注意点

> パッケージの出力先フォルダ（`GENERATE_OUTPUT_PATH`）自体は自動でクリーンされない（各シートのパッケージはそのシート処理時に個別に削除→再作成されるが、Excelから削除・リネームしたシートの古いパッケージは残り続ける）。不要になった古いパッケージを残したくない場合は、実行前に`GENERATE_OUTPUT_PATH`の中身を自分で削除しておくこと。

### 3. ファイルアップロードについて

ローカルフォルダの中身をTeams/SharePointにアップロードしたい場合、`upload-folder.bat`で送信できる。`download-folder.bat`の逆方向で、同じくAzure CLIで取得したトークンでMicrosoft Graph APIから直接アップロードする（ファイルサイズの上限を避けるため、基本はアップロードセッション＝チャンク方式で送信する。ただし0バイトファイルはチャンク方式では送信できないため、直接PUTする）。

#### 処理の流れ

1. `upload-folder.bat` を実行する
2. `clients\set-env.bat` が呼び出され、環境変数の初期値がセットされる
3. `upload-folder.ps1` が実行される
   1. Azure CLIでサインインする（未サインイン・期限切れ時はデバイスコードでのログインが必要）
   2. Microsoft Graph APIでサイト（`UPLOAD_SITE_URL`）を解決する
   3. ローカルフォルダ（`UPLOAD_LOCAL_PATH`）配下を再帰的にアップロードする
   4. ログの出力先（`COMMON_LOG_PATH`）に処理ログを出力する

#### 環境変数

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `UPLOAD_SITE_URL` | アップロード先のSharePointサイトURL（例：`https://xxx.sharepoint.com/sites/チーム名`） | `DOWNLOAD_SITE_URL`と同じ |
| `UPLOAD_SITE_PATH` | サイト内のアップロード先フォルダ（先頭はドキュメントライブラリ名、例：`Shared Documents/フォルダA`） | テスト用フォルダ（`.../ツール/納品`）が設定済み |
| `UPLOAD_SITE_TENANT_ID` | 対象のAzure ADテナントID | `DOWNLOAD_SITE_TENANT_ID`と同じ |
| `UPLOAD_LOCAL_PATH` | アップロード元のローカルフォルダ（フルパス） | `GENERATE_OUTPUT_PATH`と同じ（パッケージ作成の出力先） |
| `UPLOAD_LOG_PREFIX` | ログファイル名（`<アップロード先のフォルダ名>.log`）の先頭に付けるプレフィックス | `アップロード_` |

同名ファイルが既にサイト側にある場合は上書きされる。

#### 出力結果

| ファイル | 出力先 | 内容 |
|---|---|---|
| アップロードしたファイル一式 | アップロード先（`UPLOAD_SITE_PATH`、SharePoint側） | ローカルからアップロードしたファイル・フォルダ |
| `<アップロード先のフォルダ名>.log` | ログの出力先（`COMMON_LOG_PATH`） | 処理内容のログ（実際のファイル名には`<クライアント名または"デフォルト">_`も挟まる。詳しくは[clients\README.md](clients/README.md)を参照） |

#### 必要なもの

> **Azure CLI**が必要（`winget install --id Microsoft.AzureCLI`）。未インストールの場合、`upload-folder.ps1`がエラーで案内を表示して終了する。サインイン方法は[Azure CLIでのサインイン](#azure-cliでのサインイン)を参照。

#### 注意点

> SharePoint側のアップロード用エンドポイントとの通信が不安定な場合があり、1チャンクにつき最大8回リトライする。

> 大量のファイル・深いフォルダ構成があると時間がかかる。

## GUI版

`.bat`をコマンドプロンプトから実行する代わりに、画面から操作したい場合は`コース別パッケージ生成ツール.exe`を使う。

### 実施手順

1. `コース別パッケージ生成ツール.exe`をダブルクリックして起動する
2. 画面は「実行」「ログ」「設定」の3タブ。それぞれの使い方は以下を参照

### 注意点

> Azure CLIのデバイスコードサインインが必要な場合、URLとコードもログ欄に表示される。

### 実行タブ

- 「クライアント」ドロップダウンで、`clients`フォルダに置いたクライアントごとの設定ファイルを選べる。「デフォルト」を選べば`clients\set-env.bat`の値のまま
- 「1. ファイルダウンロード」「2. 個別パッケージの作成」「3. ファイルアップロード」のチェックボックス（現在の`DOWNLOAD_ENABLED`/`GENERATE_ENABLED`/`UPLOAD_ENABLED`の値を反映。「設定」タブで値を変更した場合や、上の「クライアント」ドロップダウンを切り替えた場合も、その時点の最新の値に更新される）で、実行する段階を選ぶ。切り替え後に手動でチェックを変更すれば、その状態が「実行」時に優先される
- 「実行」ボタンを押すと、選んだ内容で`all.bat`が呼び出され、その出力が画面のログ欄に追記表示される（実行するたびに区切り線を挟んで積み重なる。過去の実行結果も遡って確認できる）
- 実行中は「ログ」「設定」タブへの切り替えを含め、画面の操作ができなくなる（完了するまで待つ必要がある）

### ログタブ

- 「クライアント」ドロップダウンで、表示するログをクライアント別に絞り込める。「すべて」を選べば絞り込みなし（クライアント指定の有無を問わず全ログを表示）。「デフォルト」を選べばクライアント未指定で実行した分だけに絞り込める。それ以外は既存のクライアント名から選ぶ
- 「1. ファイルダウンロード」「2. 個別パッケージの作成」「3. ファイルアップロード」のラジオボタンで、確認したい段階のログを切り替える
- 選んだ段階の`COMMON_LOG_PATH`配下のログファイル（`DOWNLOAD_LOG_PREFIX`/`GENERATE_LOG_PREFIX`/`UPLOAD_LOG_PREFIX`で始まる`.log`ファイル）を、該当するものすべて連結して（新しい順に）表示する。「1. ファイルダウンロード」「3. ファイルアップロード」は実行ごとに1件しか出力されないため実質1件のみ表示されるが、「2. 個別パッケージの作成」はシートごとに複数出力されるため、それらすべてがまとめて表示される

### 設定タブ

- 「クライアント」ドロップダウンで「デフォルト」または既存のクライアント（`clients`フォルダの`set-env-*.bat`）を選ぶ
  - 「デフォルト」を選んだ場合: `clients\set-env.bat`の中身（`if not defined VAR set "VAR=値"`の各行）を一覧表示し、値を書き換えて「保存」で`clients\set-env.bat`に書き込める。テキストエディタで直接編集する代わりに使える
  - クライアントを選んだ場合: そのクライアントが上書きできる項目（ログ関連以外の全項目。書き方は[clients\README.md](clients/README.md)を参照）だけを表示する。クライアント側に値が無い項目は`clients\set-env.bat`の既定値を表示する。「保存」すると、表示されている値がそのまま`clients\set-env-<クライアント名>.bat`に書き込まれる（`clients\set-env.bat`自体は変更しない）
- 「新規作成...」でクライアント名を入力すると、`clients`フォルダに新しい空のクライアントファイル（`set-env-<クライアント名>.bat`）を作成し、クライアントに切り替える（フィールドは`clients\set-env.bat`の既定値で表示されるので、必要な項目だけ書き換えて保存する）
- 各項目のラベルは環境変数名ではなく日本語の表示名を表示する（元の環境変数名はラベルにマウスを乗せるとツールチップで確認できる）
- 「再読込」で選択中のデフォルト/クライアントの現在の内容を読み直す（保存前の変更を取り消したい場合など）

| グループ | 環境変数名 | 表示名 |
|---|---|---|
| 共通 | `COMMON_LOG_PATH` | ログの出力先 |
| ダウンロード | `DOWNLOAD_ENABLED` | 機能の有効化 |
| ダウンロード | `DOWNLOAD_SITE_URL` | ダウンロード元のサイトURL |
| ダウンロード | `DOWNLOAD_SITE_PATH` | ダウンロード元のフォルダ |
| ダウンロード | `DOWNLOAD_SITE_TENANT_ID` | テナントID |
| ダウンロード | `DOWNLOAD_LOCAL_PATH` | ダウンロード先のフォルダ |
| ダウンロード | `DOWNLOAD_LOG_PREFIX` | ログファイル名の接頭辞 |
| パッケージ作成 | `GENERATE_ENABLED` | 機能の有効化 |
| パッケージ作成 | `GENERATE_SOURCE_PATH` | 圧縮元のフォルダ |
| パッケージ作成 | `GENERATE_CONFIG_PATH` | パッケージ定義ファイル |
| パッケージ作成 | `GENERATE_SHEETS_INCLUDE` | 対象のシート名 |
| パッケージ作成 | `GENERATE_SHEETS_EXCLUDE` | 除外のシート名 |
| パッケージ作成 | `GENERATE_WORK_PATH` | 作業用のフォルダ |
| パッケージ作成 | `GENERATE_OUTPUT_PATH` | パッケージの出力先 |
| パッケージ作成 | `GENERATE_LOG_PREFIX` | ログファイル名の接頭辞 |
| アップロード | `UPLOAD_ENABLED` | 機能の有効化 |
| アップロード | `UPLOAD_SITE_URL` | アップロード先のサイトURL |
| アップロード | `UPLOAD_SITE_PATH` | アップロード先のフォルダ |
| アップロード | `UPLOAD_SITE_TENANT_ID` | テナントID |
| アップロード | `UPLOAD_LOCAL_PATH` | アップロード元のフォルダ |
| アップロード | `UPLOAD_LOG_PREFIX` | ログファイル名の接頭辞 |
